import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/common/widgets/player_bar.dart';
import 'package:material_ui/material_ui.dart';

/// The mine page's header in liquid glass, laid over [content], whose list
/// starts below it and scrolls under it: [actions] on one
/// [GlassButtonGroup] at its end, and with [showBackBtn] a back button on a
/// glass circle of its own at its start.
class MineGlassBody extends StatelessWidget {
  const MineGlassBody({
    super.key,
    required this.actions,
    required this.content,
    this.showBackBtn = false,
  });

  /// How far the header covers the content under it.
  static const extent = 6.0 + GlassButtonGroup.thickness + 4.0;

  final List<Widget> actions;
  final Widget content;
  final bool showBackBtn;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              // Scales the buttons down together where they don't fit.
              child: PlayerBar(
                left: showBackBtn
                    ? const GlassButtonGroup(children: [BackButton()])
                    : const SizedBox.shrink(),
                right: GlassButtonGroup(children: actions),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
