import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

// As the home header's: the buttons stand 14 in from the sides, and the tabs
// leave 6 under them.
const double _sideInset = 14;
const double _tabsGap = 6;

// How much more of the surface the title stands on than the header's fade
// gives: what scrolls under the title shows at about a seventh.
const double _titleBacking = 0.7;

// As AppBar's, so that a large font keeps the title a title.
const double _maxTitleTextScale = 1.34;

/// A bar that `SimpleScaffold` lays over its body rather than above it while
/// liquid glass is on, as [GlassAppBar] is, telling the body how far it
/// covers it through [HeaderOverlayInset]. A bar that builds glass bars of
/// its own, as a multi-select bar switching between two, implements it too.
abstract interface class OverlaidAppBar implements PreferredSizeWidget {}

/// A secondary page's title bar, as iOS 26's navigation bar while liquid
/// glass is on: a circle of glass to go back, the title in the middle, the
/// actions together on one capsule of glass, and, with [tabs], a pill of tabs
/// under them, all over a soft fade, floating over the content, which
/// scrolls under it. With glass off it is the Material [AppBar] it stands in
/// for, built from the same arguments.
///
/// It takes [AppBar]'s place in `SimpleScaffold.appBar`, which lays it over
/// the body; under a Material [Scaffold], see [GlassAppBarBody]. The body
/// makes room for it with [HeaderOverlayInset], read below the scaffold.
class GlassAppBar extends StatelessWidget implements OverlaidAppBar {
  const GlassAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.centerTitle,
    this.tabs,
  });

  /// Whether the bars are glass: the 液态玻璃 switch, read once at startup.
  static bool get enabled => debugEnabled ?? GlassSurfaces.installed;

  @visibleForTesting
  static bool? debugEnabled;

  /// How tall and, alone, how wide a button on the bar is, as iOS 26's.
  static const double buttonSize = 44;

  /// As [AppBar.leading]. On glass it stands on a circle of glass; without
  /// it, a route that can be popped gets a glass back button.
  final Widget? leading;

  final bool automaticallyImplyLeading;

  final Widget? title;

  /// As [AppBar.actions]. On glass they stand side by side on one capsule of
  /// glass, each as it is, IconButtons and TextButtons 44 dp tall; a lone
  /// one makes it a circle. Childless [SizedBox]es, which space Material's
  /// actions from the edge, are left out there.
  final List<Widget>? actions;

  /// As [AppBar.centerTitle]. On glass the title is centered unless false.
  final bool? centerTitle;

  /// A second row on glass, under the title, while glass is on. With glass
  /// off the page keeps its own [TabBar] in the body.
  final LiquidGlassTabBar? tabs;

  @override
  Size get preferredSize {
    var height = kToolbarHeight;
    if (tabs case final tabs? when enabled) {
      height += tabs.height + _tabsGap;
    }
    return Size.fromHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return AppBar(
        leading: this.leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        title: this.title,
        actions: this.actions,
        centerTitle: centerTitle,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appBarTheme = AppBarTheme.of(context);

    Widget? leading = this.leading;
    if (leading != null) {
      leading = _GlassButtons(children: [leading]);
    } else if (automaticallyImplyLeading) {
      final route = ModalRoute.of(context);
      if (route?.impliesAppBarDismissal ?? false) {
        leading = _GlassBackButton(close: route!.fullscreenDialog);
      }
    }

    final actions = [
      for (final action in this.actions ?? const <Widget>[])
        if (action is! SizedBox || action.child != null) action,
    ];

    Widget? title = this.title;
    if (title != null) {
      title = MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTitleTextScale,
        child: DefaultTextStyle(
          style:
              appBarTheme.titleTextStyle ??
              theme.textTheme.titleLarge!.copyWith(
                color: colorScheme.onSurface,
              ),
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          child: Semantics(
            namesRoute: switch (defaultTargetPlatform) {
              .iOS || .macOS => null,
              _ => true,
            },
            header: true,
            child: title,
          ),
        ),
      );
    }

    Widget bar = SizedBox(
      height: kToolbarHeight,
      child: NavigationToolbar(
        leading: leading == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: _sideInset),
                child: Center(widthFactor: 1, child: leading),
              ),
        middle: title,
        trailing: actions.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: _sideInset),
                child: Center(
                  widthFactor: 1,
                  child: _GlassButtons(children: actions),
                ),
              ),
        centerMiddle: centerTitle ?? true,
      ),
    );
    if (tabs case final tabs?) {
      bar = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _sideInset,
              0,
              _sideInset,
              _tabsGap,
            ),
            child: tabs,
          ),
        ],
      );
    }

    // The status bar's icons read on the fade as on Material's bar.
    final overlayStyle =
        ThemeData.estimateBrightnessForColor(colorScheme.surface) == .dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return Semantics(
      container: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            appBarTheme.systemOverlayStyle ??
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarBrightness: overlayStyle.statusBarBrightness,
              statusBarIconBrightness: overlayStyle.statusBarIconBrightness,
              systemStatusBarContrastEnforced:
                  overlayStyle.systemStatusBarContrastEnforced,
            ),
        child: LiquidGlassHeader(
          // The title reads on the fade itself, not on glass as the home
          // header's tabs do, so the fade is thicker behind the bar's rows,
          // easing back to the header's own by their bottom.
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface.withValues(alpha: _titleBacking),
                  colorScheme.surface.withValues(alpha: _titleBacking),
                  colorScheme.surface.withValues(alpha: 0),
                ],
                stops: const [0, 0.75, 1],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: LiquidGlassGroup(child: bar),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays [appBar] over [body] while glass is on: the body takes the whole
/// height and scrolls under the bar, and reads how far it covers it from
/// [HeaderOverlayInset]. With glass off, just [body].
///
/// `SimpleScaffold` does this for an [OverlaidAppBar]. Under a Material
/// [Scaffold], pass this as the body and leave the scaffold's own appBar
/// null while glass is on:
///
/// ```dart
/// final appBar = GlassAppBar(title: const Text('日志'));
/// return Scaffold(
///   appBar: GlassAppBar.enabled ? null : appBar,
///   body: GlassAppBarBody(appBar: appBar, body: body),
/// );
/// ```
class GlassAppBarBody extends StatelessWidget {
  const GlassAppBarBody({
    super.key,
    required this.appBar,
    required this.body,
  });

  final PreferredSizeWidget appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (!GlassAppBar.enabled) {
      return body;
    }
    final inset =
        MediaQuery.paddingOf(context).top + appBar.preferredSize.height;
    return Stack(
      children: [
        // The inset covers the status bar, as Material's bar does.
        Positioned.fill(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: HeaderOverlayInset(inset: inset, child: body),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: appBar),
      ],
    );
  }
}

/// Room for the bar over it, read where this is built: the first child of a
/// [ListView] or [Column] built in the page's own build, whose context is
/// above its scaffold and so sees no [HeaderOverlayInset].
class HeaderOverlaySpace extends StatelessWidget {
  const HeaderOverlaySpace({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: HeaderOverlayInset.of(context));
}

/// [HeaderOverlaySpace] at the start of a [CustomScrollView], as
/// [HeaderOverlayInset.sliver] read where it is built.
class SliverHeaderOverlaySpace extends StatelessWidget {
  const SliverHeaderOverlaySpace({super.key});

  @override
  Widget build(BuildContext context) => HeaderOverlayInset.sliver(context);
}

/// [children] side by side on one capsule of glass, as iOS 26 groups a bar's
/// buttons: a circle around a lone one. Each keeps its own press, a platter
/// without a ripple.
class _GlassButtons extends StatelessWidget {
  const _GlassButtons({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const size = Size.square(GlassAppBar.buttonSize);
    return Stack(
      children: [
        // Sized by the buttons, so that it is empty, and not drawn, while
        // they all hide.
        Positioned.fill(
          child: LiquidGlass(
            style: LiquidGlassStyle.regular(colorScheme),
            shadows: floatingGlassShadows(colorScheme),
          ),
        ),
        Theme(
          data: GlassSurfaces.withoutRipples(theme).copyWith(
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: size,
                tapTargetSize: .shrinkWrap,
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                minimumSize: size,
                tapTargetSize: .shrinkWrap,
              ),
            ),
          ),
          child: SizedBox(
            height: GlassAppBar.buttonSize,
            child: Row(mainAxisSize: .min, children: children),
          ),
        ),
      ],
    );
  }
}

/// The way back on a circle of glass, as [BackButton], or as [CloseButton]
/// for a full-screen dialog.
class _GlassBackButton extends StatelessWidget {
  const _GlassBackButton({required this.close});

  final bool close;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final localizations = MaterialLocalizations.of(context);
    return SizedBox.square(
      dimension: GlassAppBar.buttonSize,
      child: LiquidGlassButton(
        tooltip: close
            ? localizations.closeButtonTooltip
            : localizations.backButtonTooltip,
        onTap: () => Navigator.maybePop(context),
        shadows: floatingGlassShadows(colorScheme),
        child: Center(
          child: Icon(
            close ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
