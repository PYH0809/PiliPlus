import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:material_ui/material_ui.dart';

/// The 投稿 tab's categories on a pill of glass over [child], their lists,
/// which start below it and scroll under it, as the home page's categories
/// over its feeds.
class GlassCategoryTabs extends StatelessWidget {
  const GlassCategoryTabs({
    super.key,
    required this.controller,
    required this.labels,
    required this.child,
  });

  /// How far the row covers the lists: 6 above the pill, 40 for it, 4 below.
  static const extent = 6.0 + 40.0 + 4.0;

  final TabController controller;
  final List<String> labels;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: HeaderOverlayInset(inset: extent, child: child),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LiquidGlassHeader(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              // Centered as the home page's, as wide as the categories
              // until they fill the row and scroll in it.
              child: Center(
                child: LiquidGlassTabBar(
                  controller: controller,
                  labels: labels,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [header], the row a list floats back in, as it stands under a header laid
/// over the list, as the search results' filters do: it floats back just
/// below that header, the room above it clear so the list shows through the
/// header, and slides away under it. The list then starts with it rather
/// than with [HeaderOverlayInset.sliver]. Without a header over the list it
/// is [header].
class FloatingUnderOverlay extends StatelessWidget {
  const FloatingUnderOverlay({super.key, required this.header});

  final SliverFloatingHeaderWidget header;

  @override
  Widget build(BuildContext context) {
    final inset = HeaderOverlayInset.of(context);
    if (inset == 0) {
      return header;
    }
    return SliverFloatingHeaderWidget(
      backgroundColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(top: inset),
        child: ColoredBox(color: header.backgroundColor, child: header.child),
      ),
    );
  }
}
