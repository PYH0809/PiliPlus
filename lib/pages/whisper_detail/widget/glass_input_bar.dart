import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// The input bar of a chat, floating on glass over the messages as in iOS's
/// Messages: [leading], usually a circle of glass, beside a capsule of glass
/// holding [field] and [trailing], which grows taller with the text, its
/// bottom staying level with [leading]'s.
class GlassInputBar extends StatelessWidget {
  const GlassInputBar({
    super.key,
    required this.leading,
    required this.field,
    required this.trailing,
  });

  /// A line's height: the capsule's at its shortest and [leading]'s.
  static const height = 40.0;
  static const margin = 12.0;

  /// The room under the bar, above the keyboard or a panel.
  static const gap = 8.0;

  final Widget leading;
  final Widget field;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const .fromLTRB(margin, 0, margin, gap),
      child: LiquidGlassGroup(
        child: Row(
          crossAxisAlignment: .end,
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: LiquidGlass(
                style: LiquidGlassStyle.regular(colorScheme),
                borderRadius: const .all(.circular(height / 2)),
                shadows: floatingGlassShadows(colorScheme),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: height),
                  child: Row(
                    crossAxisAlignment: .end,
                    children: [
                      Expanded(child: field),
                      trailing,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [field]'s decoration: bare on the glass, a line [height] tall.
  static InputDecoration decoration(String hintText) => InputDecoration(
    hintText: hintText,
    filled: false,
    isDense: true,
    border: InputBorder.none,
    contentPadding: const .fromLTRB(16, 8, 4, 8),
  );
}

/// The button at the end of a [GlassInputBar]'s capsule: [icon] bare on the
/// glass, or, [filled], on a circle of the theme's color inset as far all
/// round, as iOS's send button is.
class GlassInputButton extends StatelessWidget {
  const GlassInputButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  static const _inset = 4.0;

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platter = glassPlatterColor(colorScheme);
    return Padding(
      padding: .all(filled ? _inset : 0),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style:
            IconButton.styleFrom(
              fixedSize: .square(
                GlassInputBar.height - (filled ? 2 * _inset : 0),
              ),
              minimumSize: .zero,
              padding: .zero,
              tapTargetSize: .shrinkWrap,
              iconSize: filled ? 20 : 22,
              shape: const CircleBorder(),
              backgroundColor: filled ? colorScheme.primary : null,
              foregroundColor: filled
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              splashFactory: NoSplash.splashFactory,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.pressed) ||
                        states.contains(WidgetState.focused)
                    ? platter
                    : Colors.transparent,
              ),
            ),
      ),
    );
  }
}
