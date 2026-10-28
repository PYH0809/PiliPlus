import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:material_ui/material_ui.dart';

/// The space page's bar in liquid glass, as iOS 26's: the way back on a
/// circle of glass and the other buttons on one capsule, floating on the
/// banner, and on the bar once it collapses, 14 dp in from the sides.
abstract final class MemberGlassBar {
  static const double inset = 14;

  /// As tall as a [GlassButtonGroup].
  static const double buttonSize = GlassButtonGroup.thickness;

  /// Room for the back button, then 12 dp to the title.
  static const double leadingWidth = inset + buttonSize + 12;

  /// The back button, where the page can go back.
  static Widget? leading(BuildContext context) {
    if (!(ModalRoute.of(context)?.impliesAppBarDismissal ?? false)) {
      return null;
    }
    return const Padding(
      padding: EdgeInsets.only(left: inset),
      child: Align(
        alignment: Alignment.centerLeft,
        child: MemberGlassBackButton(),
      ),
    );
  }

  /// [buttons], the bar's own, on one capsule [inset] in from the end; the
  /// gaps they kept between them go.
  static List<Widget> actions(List<Widget> buttons) => [
    GlassButtonGroup(
      children: [
        for (final button in buttons)
          if (button is! SizedBox || button.child != null) button,
      ],
    ),
    const SizedBox(width: inset),
  ];
}

/// The way back on a circle of glass, as tall as the capsule beside it.
class MemberGlassBackButton extends StatelessWidget {
  const MemberGlassBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox.square(
      dimension: MemberGlassBar.buttonSize,
      child: LiquidGlassButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onTap: () => Navigator.maybePop(context),
        styleOf: GlassButtonGroup.styleOf,
        shadows: GlassButtonGroup.shadowsOf(colorScheme),
        child: Center(
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
