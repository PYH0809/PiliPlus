import 'dart:ui' show lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_alert_actions.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_panel.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

// FlClash's menu and alert, after iOS: a menu is a card of rows inset in it,
// its corners concentric with theirs; an alert as round as UIAlertController.
const double _menuInset = 8;
const double _menuRowRadius = 16;
const double _menuRadius = _menuRowRadius + _menuInset;
const double _alertRadius = 34;

// As UIAlertController, an alert grows in from 1.2 times its size and only
// fades out; a press swells it by about 4 dp a side.
const double _alertEntryScale = 1.2;
const double _alertPressGrowth = 0.025;
final _pressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 311,
  ratio: 0.593,
);

/// Draws every dialog and popup menu on liquid glass, as FlClash's alerts and
/// menus, a menu growing out of its button, through the hooks that
/// `lib/scripts/material/surface_builders.patch` adds to material_ui;
/// [themed] sets their text and spacing to match. Nothing changes at the call
/// sites.
abstract final class GlassSurfaces {
  static void install() {
    SurfaceBuilders.dialog = (context, shape, child) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      return _AlertMotion(
        child: GlassPanel(
          style: LiquidGlassStyle.alert(colorScheme),
          rim: LiquidGlassRim.alert(colorScheme),
          shadows: menuShadows(colorScheme),
          radius: _alertRadius,
          child: Theme(
            data: _withoutRipples(theme),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      );
    };
    SurfaceBuilders.dialogActions = (context, actions) =>
        GlassAlertActions(actions: actions);
    SurfaceBuilders.popupMenu = (context, shape, child, animation, anchor) {
      final theme = Theme.of(context);
      return GlassMenuMorph(
        animation: animation,
        anchor: anchor,
        radius: _menuRadius,
        child: Theme(
          data: _withoutRipples(theme).copyWith(
            dividerTheme: theme.dividerTheme.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.14),
              thickness: 1,
              space: _menuInset * 2 + 1,
            ),
          ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
    };
    SurfaceBuilders.popupMenuItemShape = const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(_menuRowRadius)),
    );
    // A platter is a press; the current value takes a check, as FlClash's.
    SurfaceBuilders.popupMenuCheck = const Icon(Icons.check_rounded, size: 18);
  }

  // On glass a pressed row stands on a platter, without a ripple.
  static ThemeData _withoutRipples(ThemeData theme) => theme.copyWith(
    splashFactory: NoSplash.splashFactory,
    highlightColor: theme.colorScheme.brightness == Brightness.dark
        ? const Color(0x40CCCCCC)
        : const Color(0x66BCBCBC),
  );

  /// [theme] with FlClash's alert and menu text, spacing and scrim.
  static ThemeData themed(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final textTheme = theme.textTheme;
    return theme.copyWith(
      dialogTheme: theme.dialogTheme.copyWith(
        barrierColor: colorScheme.scrim.withValues(alpha: dark ? 0.48 : 0.2),
        titleTextStyle:
            (theme.dialogTheme.titleTextStyle ?? textTheme.titleMedium)
                ?.copyWith(
                  fontSize: 17,
                  height: 22 / 17,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          height: 20 / 15,
          letterSpacing: 0,
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: dark ? 1 : 0.85,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 348),
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(
        menuPadding: const EdgeInsets.all(_menuInset),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            height: 20 / 15,
            letterSpacing: 0,
            color: colorScheme.onSurface.withValues(
              alpha: states.contains(WidgetState.disabled) ? 0.38 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertMotion extends StatefulWidget {
  const _AlertMotion({required this.child});

  final Widget child;

  @override
  State<_AlertMotion> createState() => _AlertMotionState();
}

class _AlertMotionState extends State<_AlertMotion>
    with TickerProviderStateMixin {
  late final _swell = GlassSpring(this, 0);
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context)?.animation;
  }

  @override
  void dispose() {
    _swell.dispose();
    super.dispose();
  }

  void _press(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _swell.jumpTo(target);
    } else {
      _swell.springTo(target, _pressSpring);
    }
  }

  // material_ui's DialogRoute only fades, so this is the alert's one scale:
  // in from 1.2 times its size as the route opens, none as it closes.
  double get _entry {
    final route = _route;
    if (route == null ||
        route.status == AnimationStatus.reverse ||
        MediaQuery.disableAnimationsOf(context)) {
      return 1;
    }
    return lerpDouble(
      _alertEntryScale,
      1,
      Curves.easeOutCubic.transform(route.value),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _press(1),
      onPointerUp: (_) => _press(0),
      onPointerCancel: (_) => _press(0),
      child: AnimatedBuilder(
        animation: Listenable.merge([?_route, _swell]),
        builder: (context, child) => Transform.scale(
          scale: _entry * (1 + _alertPressGrowth * _swell.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
