import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// Tabs on one pill of liquid glass. The current tab stands on a platter that
/// slides with [controller] as the pages do.
class LiquidGlassTabBar extends StatelessWidget {
  const LiquidGlassTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.onTap,
    this.height = 40,
  });

  final TabController controller;
  final List<String> labels;
  final ValueChanged<int>? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    const inset = 4.0;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: LiquidGlass(
              style: LiquidGlassStyle.pill(colorScheme),
              shadows: floatingGlassShadows(colorScheme),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(inset),
            child: TabBar(
              controller: controller,
              tabs: [
                for (final label in labels)
                  Tab(height: height - 2 * inset, text: label),
              ],
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              indicator: ShapeDecoration(
                color: glassPlatterColor(colorScheme),
                shape: const StadiumBorder(),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurface,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}
