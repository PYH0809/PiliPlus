import 'dart:ui' show lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_alert_actions.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_press.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_panel.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_switch.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
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
  /// Whether [install] ran: dialogs and menus are glass, and call sites may
  /// lay theirs out as FlClash's.
  static bool get installed => _installed;
  static bool _installed = false;

  static void install() {
    _installed = true;
    SurfaceBuilders.dialog = (context, shape, child) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      return _AlertMotion(
        child: GlassPanel(
          style: _alertStyle(colorScheme),
          rim: LiquidGlassRim.alert(colorScheme),
          shadows: menuShadows(colorScheme),
          radius: _alertRadius,
          child: _OnGlass(
            child: Theme(
              data: _withoutRipples(theme),
              child: Material(type: MaterialType.transparency, child: child),
            ),
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
        child: _OnGlass(
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
        ),
      );
    };
    SurfaceBuilders.popupMenuItemShape = const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(_menuRowRadius)),
    );
    // A platter is a press; the current value takes a check, as FlClash's.
    SurfaceBuilders.popupMenuCheck = const Icon(Icons.check_rounded, size: 18);
    // As iOS's: a press on a menu's button opens it, and can slide on to an
    // item; it closes back into the button as a drop of glass.
    SurfaceBuilders.popupMenuButton = (context, open, button) =>
        GlassMenuPress(open: open, child: button);
    SurfaceBuilders.popupMenuReverseDuration = glassMenuReturn;
    // As FlClash's: a press lifts the thumb into a lens over the track.
    SurfaceBuilders.switchBuilder = (context, value, onChanged) =>
        GlassSwitch(value: value, onChanged: onChanged);
    // The copy and paste menu floats over the text as iOS's edit menu does,
    // a capsule of the menus' glass.
    SurfaceBuilders.textSelectionToolbar = (context, shape, child) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      return GlassPanel(
        style: LiquidGlassStyle.menu(colorScheme),
        rim: LiquidGlassRim.menu(colorScheme),
        shadows: menuShadows(colorScheme),
        radius: switch (shape) {
          RoundedRectangleBorder(:final borderRadius) =>
            borderRadius.resolve(Directionality.of(context)).topLeft.x,
          _ => 0,
        },
        child: Theme(
          data: _withoutRipples(theme),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
    };
  }

  /// A floating card of the menus' glass, with their rim and shadow, for a
  /// call site's own popover or banner.
  static Widget panel(
    BuildContext context, {
    required double radius,
    required Widget child,
  }) {
    final colorScheme = ColorScheme.of(context);
    return GlassPanel(
      style: LiquidGlassStyle.menu(colorScheme),
      rim: LiquidGlassRim.menu(colorScheme),
      shadows: menuShadows(colorScheme),
      radius: radius,
      child: _OnGlass(child: child),
    );
  }

  /// Whether [context] is on one of these surfaces, for controls that fill
  /// themselves as glass controls are there and as Material's elsewhere.
  static bool onGlass(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OnGlass>() != null;

  /// A pill of glass, as a toast's, for a short note over content.
  static Widget pill(BuildContext context, {required Widget child}) {
    final colorScheme = ColorScheme.of(context);
    return LiquidGlass(
      style: LiquidGlassStyle.pill(colorScheme),
      shadows: floatingGlassShadows(colorScheme),
      child: child,
    );
  }

  // Thicker than FlClash's, as an iOS alert is: over busy covers its text
  // reads on a soft wash of their colors rather than the covers themselves.
  static LiquidGlassStyle _alertStyle(ColorScheme colorScheme) {
    final menu = LiquidGlassStyle.menu(colorScheme);
    final dark = colorScheme.brightness == Brightness.dark;
    return LiquidGlassStyle(
      tint: menu.tint.withValues(alpha: dark ? 0.8 : 0.74),
      contrast: menu.contrast,
      blur: 30,
      saturation: dark ? 1.3 : 1.4,
      brightness: menu.brightness,
      rim: 0,
    );
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

class _OnGlass extends InheritedWidget {
  const _OnGlass({required super.child});

  @override
  bool updateShouldNotify(_OnGlass oldWidget) => false;
}
