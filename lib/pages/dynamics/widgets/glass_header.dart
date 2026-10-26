import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:material_ui/material_ui.dart';

/// The dynamics page's header in liquid glass, laid over the feed: the tabs
/// on a glass pill between [leading] and [trailing], usually [GlassCircle]s.
class DynamicsGlassHeader extends StatelessWidget {
  const DynamicsGlassHeader({
    super.key,
    required this.controller,
    required this.labels,
    this.onTap,
    this.leading,
    this.trailing,
    this.fade = 16,
  });

  /// How far the header covers the content under it, logged in or not.
  static const extent = 6.0 + 40.0 + 4.0;

  final TabController controller;
  final List<String> labels;
  final ValueChanged<int>? onTap;
  final Widget? leading;
  final Widget? trailing;

  /// How far the header fades out past its bottom: none where the content
  /// starts below it rather than scrolling under it.
  final double fade;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassHeader(
      fade: fade,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        child: Row(
          children: [
            if (leading case final leading?) ...[
              leading,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: LiquidGlassTabBar(
                controller: controller,
                labels: labels,
                onTap: onTap,
                labelStyle:
                    TabBarTheme.of(context).labelStyle
                        ?.copyWith(fontSize: 13) ??
                    const TextStyle(fontSize: 13),
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// A 40 dp circle of glass holding [icon], as the header's buttons.
class GlassCircle extends StatelessWidget {
  const GlassCircle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox.square(
      dimension: 40,
      child: LiquidGlassButton(
        tooltip: tooltip,
        onTap: onTap,
        shadows: floatingGlassShadows(colorScheme),
        child: Center(
          child: Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Lays [header] over [content], whose lists start below it and scroll under
/// it, or, with [below], lays [content] out below it, for the panel of UPs on
/// top, which scrolls sideways.
class DynamicsGlassBody extends StatelessWidget {
  const DynamicsGlassBody({
    super.key,
    required this.header,
    required this.content,
    this.below = false,
  });

  final Widget header;
  final Widget content;
  final bool below;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          // Logged in or not, so that the feed doesn't jump.
          child: HeaderOverlayInset(
            inset: DynamicsGlassHeader.extent,
            child: below
                ? Builder(
                    builder: (context) =>
                        HeaderOverlayInset.below(context, child: content),
                  )
                : content,
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: header),
      ],
    );
  }
}
