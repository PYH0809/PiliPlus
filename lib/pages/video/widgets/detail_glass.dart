import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// The video page's tabs in liquid glass: the tabs on a pill, then a 发弹幕
/// pill and a round danmaku switch, as the home page's header lays them out.
class GlassDetailTabRow extends StatelessWidget {
  const GlassDetailTabRow({
    super.key,
    required this.controller,
    required this.tabs,
    this.replyCount,
    this.showPlatter = true,
    this.onTap,
    required this.onSendDanmaku,
    required this.showDanmaku,
    required this.onToggleDanmaku,
    this.compact = false,
  });

  /// How tall the row stands: 6 above the pills, 40 for them, 4 below.
  static const extent = 6.0 + 40.0 + 4.0;

  final TabController controller;

  /// The tabs' names. One named 评论 shows [replyCount] after it.
  final List<String> tabs;
  final RxInt? replyCount;
  final bool showPlatter;
  final ValueChanged<int>? onTap;
  final VoidCallback onSendDanmaku;
  final RxBool showDanmaku;
  final VoidCallback onToggleDanmaku;

  /// Shows only the icon to send danmaku, to keep room for the tabs.
  final bool compact;

  /// Whether a row [width] wide, as the landscape column at 280 dp, is too
  /// narrow for [tabCount] tabs beside the words 发弹幕. The page tells the row
  /// rather than the row measuring itself: under a LayoutBuilder the tab bar
  /// would rebuild for a new MediaQuery before its new controller reached it,
  /// holding the one the page has just disposed.
  static bool isCompact(double width, int tabCount) =>
      width - 28 < 140.0 + 72 * tabCount;

  static String replyLabel(int count) =>
      '评论${count == -1 ? '' : ' ${NumUtils.numFormat(count)}'}';

  Widget _tabBar(TextStyle labelStyle) {
    Widget tabBar(List<String> labels) => LiquidGlassTabBar(
      controller: controller,
      labels: labels,
      onTap: onTap,
      labelStyle: labelStyle,
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      showPlatter: showPlatter,
    );
    final replyCount = this.replyCount;
    if (replyCount == null || !tabs.contains('评论')) {
      return tabBar(tabs);
    }
    return Obx(() {
      final label = replyLabel(replyCount.value);
      return tabBar([
        for (final tab in tabs) tab == '评论' ? label : tab,
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final shadows = floatingGlassShadows(colorScheme);
    final labelStyle =
        TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
        const TextStyle(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: SizedBox(
        height: 40,
        child: LiquidGlassGroup(
          child: Row(
            children: [
              if (tabs.isEmpty)
                const Spacer()
              else
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _tabBar(labelStyle),
                  ),
                ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                width: compact ? 40 : null,
                child: LiquidGlassButton(
                  tooltip: compact ? '发弹幕' : null,
                  onTap: onSendDanmaku,
                  shadows: shadows,
                  child: compact
                      ? Center(
                          child: Icon(
                            Icons.comment_outlined,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              '发弹幕',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 40,
                child: Obx(() {
                  final enabled = showDanmaku.value;
                  return LiquidGlassButton(
                    tooltip: enabled ? '关闭弹幕' : '开启弹幕',
                    onTap: onToggleDanmaku,
                    shadows: shadows,
                    child: Center(
                      child: Icon(
                        enabled ? CustomIcons.dm_on : CustomIcons.dm_off,
                        size: 22,
                        color: enabled
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The comments' order on glass: what they are sorted by, and a small glass
/// pill that switches it.
class GlassReplySortRow extends StatelessWidget {
  const GlassReplySortRow({
    super.key,
    required this.desc,
    required this.label,
    required this.onSort,
  });

  final String desc;
  final String label;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(desc, style: const TextStyle(fontSize: 13)),
          SizedBox(
            height: 30,
            child: LiquidGlassButton(
              tooltip: '排序',
              onTap: onSort,
              shadows: floatingGlassShadows(colorScheme),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.sort,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The button to write a comment, a drop of glass in the theme's color.
class GlassReplyFab extends StatelessWidget {
  const GlassReplyFab({super.key, required this.onTap});

  static const size = 56.0;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: LiquidGlassButton(
        tooltip: '发表评论',
        onTap: onTap,
        styleOf: (colorScheme) =>
            LiquidGlassStyle.tinted(colorScheme, colorScheme.primary),
        shadows: floatingGlassShadows(colorScheme),
        child: Center(
          child: Icon(Icons.reply, color: colorScheme.onPrimary),
        ),
      ),
    );
  }
}
