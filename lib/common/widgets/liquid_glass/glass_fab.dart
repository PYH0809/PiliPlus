import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:material_ui/material_ui.dart';

/// A page's floating action button. With the liquid glass switch on, a drop
/// of glass in the theme's color that swells under the finger, as the reply
/// buttons are; with it off, Material's [FloatingActionButton], as before.
///
/// On glass it keeps Material's footprint, 56 dp high and padded as Material
/// pads it, a circle or a capsule, so a page lays it out and slides it away
/// just as it did the Material one, and keeps [shadowReach] free above it,
/// so that a [SlideTransition] by its own height takes the shadow out of
/// sight with it. Buttons stacked one over another go in a [GlassFabGroup].
///
/// Already on glass, as on a panel over the full-screen video, it takes no
/// pane of its own, as glass never sits on glass, and is filled instead, as
/// an alert's default action is.
class GlassFab extends StatelessWidget {
  /// A round button holding [child], as [FloatingActionButton.new].
  const GlassFab({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.heroTag = _materialHeroTag,
    required Widget this.child,
  }) : icon = null,
       label = null;

  /// A capsule holding [icon] before [label], as
  /// [FloatingActionButton.extended].
  const GlassFab.extended({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.heroTag = _materialHeroTag,
    this.icon,
    required Widget this.label,
  }) : child = null;

  static const size = 56.0;

  /// How far the shadow on glass reaches above the button.
  static const shadowReach = 24.0;

  // Stands for Material's own default hero tag, which is private.
  static const Object _materialHeroTag = Object();

  // As an alert's default action, the fill on glass shows this much of
  // itself while pressed.
  static const _pressedFillShare = 0.4;
  static const _pressedDarkFillShare = 0.5;

  final VoidCallback? onPressed;
  final String? tooltip;

  /// Material's [FloatingActionButton.heroTag], with the switch off; its own
  /// default unless given.
  final Object? heroTag;
  final Widget? child;
  final Widget? icon;
  final Widget? label;

  Widget _material() {
    final materialTag = identical(heroTag, _materialHeroTag);
    if (label case final label?) {
      return materialTag
          ? FloatingActionButton.extended(
              onPressed: onPressed,
              tooltip: tooltip,
              icon: icon,
              label: label,
            )
          : FloatingActionButton.extended(
              onPressed: onPressed,
              tooltip: tooltip,
              heroTag: heroTag,
              icon: icon,
              label: label,
            );
    }
    return materialTag
        ? FloatingActionButton(
            onPressed: onPressed,
            tooltip: tooltip,
            child: child,
          )
        : FloatingActionButton(
            onPressed: onPressed,
            tooltip: tooltip,
            heroTag: heroTag,
            child: child,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassSurfaces.installed) {
      return _material();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = colorScheme.onPrimary;
    final Widget content = IconTheme.merge(
      data: IconThemeData(color: foreground, size: 24),
      child: DefaultTextStyle(
        style: theme.textTheme.labelLarge!.copyWith(color: foreground),
        maxLines: 1,
        overflow: .ellipsis,
        child: switch (label) {
          // As Material pads an extended button.
          final label? => SizedBox(
            height: size,
            child: Padding(
              padding: .directional(start: icon == null ? 20 : 16, end: 20),
              child: Row(
                mainAxisSize: .min,
                spacing: 8,
                // Squeezed, by a narrow window or large text, the label
                // ends in an ellipsis inside the capsule rather than spill
                // past it.
                children: [
                  ?icon,
                  Flexible(child: label),
                ],
              ),
            ),
          ),
          null => SizedBox.square(
            dimension: size,
            child: Center(child: child),
          ),
        },
      ),
    );

    if (GlassSurfaces.onGlass(context) ||
        context.findAncestorWidgetOfExactType<VideoGlass>() != null) {
      return MergeSemantics(child: _filled(colorScheme, content));
    }

    Widget button = LiquidGlassButton(
      tooltip: tooltip,
      onTap: onPressed,
      styleOf: (_) => LiquidGlassStyle.tinted(colorScheme, colorScheme.primary),
      shadows: floatingGlassShadows(colorScheme),
      child: content,
    );
    // The focus ring is drawn in the primary color, which the tint would
    // swallow; in the content's color it shows.
    button = Theme(
      data: theme.copyWith(
        colorScheme: colorScheme.copyWith(primary: foreground),
      ),
      child: button,
    );
    return MergeSemantics(
      child: Padding(
        padding: const .only(top: shadowReach),
        child: button,
      ),
    );
  }

  Widget _filled(ColorScheme colorScheme, Widget content) {
    final fill = colorScheme.primary;
    final foreground = colorScheme.onPrimary;
    final pressedShare = colorScheme.brightness == Brightness.dark
        ? _pressedDarkFillShare
        : _pressedFillShare;
    final Widget button = TextButton(
      onPressed: onPressed,
      style:
          TextButton.styleFrom(
            foregroundColor: foreground,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: .shrinkWrap,
            shape: label == null ? const CircleBorder() : const StadiumBorder(),
            splashFactory: NoSplash.splashFactory,
          ).copyWith(
            backgroundColor: WidgetStateProperty<Color?>.fromMap({
              WidgetState.pressed: fill.withValues(
                alpha: fill.a * pressedShare,
              ),
              WidgetState.any: fill,
            }),
            overlayColor: WidgetStateProperty<Color?>.fromMap({
              WidgetState.focused: foreground.withValues(alpha: 0.1),
              WidgetState.pressed: Colors.transparent,
              WidgetState.hovered: foreground.withValues(alpha: 0.08),
            }),
          ),
      child: content,
    );
    if (tooltip case final tooltip?) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}

/// Round floating buttons stacked at a page's end, as the blacklist's import
/// and add. On glass they stand on one pane, as iOS 26 groups a toolbar's
/// buttons, a [GlassButtonGroup] down the page; without it, Material's
/// buttons a margin apart, as before.
class GlassFabGroup extends StatelessWidget {
  const GlassFabGroup({super.key, required this.children});

  /// The buttons, top to bottom, each a [GlassFab.new].
  final List<GlassFab> children;

  @override
  Widget build(BuildContext context) {
    if (!GlassSurfaces.installed) {
      return Column(
        spacing: kFloatingActionButtonMargin,
        mainAxisSize: .min,
        children: children,
      );
    }
    return Padding(
      padding: const .only(top: GlassFab.shadowReach),
      child: GlassButtonGroup(
        direction: .vertical,
        children: [
          for (final fab in children)
            IconButton(
              tooltip: fab.tooltip,
              onPressed: fab.onPressed,
              icon: fab.child!,
            ),
        ],
      ),
    );
  }
}
