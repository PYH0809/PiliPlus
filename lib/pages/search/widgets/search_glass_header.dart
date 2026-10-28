import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/pages/dynamics/widgets/glass_header.dart'
    show GlassCircle;
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

/// The search pages' bar in liquid glass, laid out as the home page's
/// header: a round back button, then [field] on a capsule of glass, which
/// holds its own buttons. With [onFieldTap] the capsule is a button.
class SearchGlassBar extends StatelessWidget {
  const SearchGlassBar({
    super.key,
    required this.field,
    this.onFieldTap,
  });

  /// How tall the bar stands: 6 above the glass, 40 for it, 4 below.
  static const extent = 6.0 + 40.0 + 4.0;

  final Widget field;
  final VoidCallback? onFieldTap;

  // As BackButtonIcon picks it.
  static IconData _backIcon(TargetPlatform platform) => switch (platform) {
    .iOS || .macOS => Icons.arrow_back_ios_new_rounded,
    _ => Icons.arrow_back,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final shadows = floatingGlassShadows(colorScheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            GlassCircle(
              icon: _backIcon(Theme.of(context).platform),
              tooltip: '返回',
              onTap: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: switch (onFieldTap) {
                final onTap? => LiquidGlassButton(
                  onTap: onTap,
                  shadows: shadows,
                  child: field,
                ),
                null => LiquidGlass(
                  style: LiquidGlassStyle.regular(colorScheme),
                  shadows: shadows,
                  child: field,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays [header], a [SearchGlassBar] and what goes below it, over [content]
/// below the status bar, as the home page lays out its own: [content] starts
/// [extent] down and scrolls under it, as it reads [HeaderOverlayInset].
class SearchGlassScaffold extends StatelessWidget {
  const SearchGlassScaffold({
    super.key,
    required this.extent,
    required this.header,
    required this.content,
  });

  final double extent;
  final Widget header;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final brightness = ColorScheme.of(context).brightness;
    final padding = MediaQuery.viewPaddingOf(context);
    // The status bar's icons as over the app bar the page has without glass.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: brightness,
        statusBarIconBrightness: brightness.reverse,
        systemStatusBarContrastEnforced: false,
      ),
      child: Material(
        child: Padding(
          padding: EdgeInsets.only(top: padding.top),
          child: Stack(
            children: [
              Positioned.fill(
                child: HeaderOverlayInset(inset: extent, child: content),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LiquidGlassHeader(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: padding.left,
                      right: padding.right,
                    ),
                    child: header,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
