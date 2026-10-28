import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// Buttons side by side on one pane of glass, as iOS 26 groups a toolbar's:
/// evenly spaced, without dividers, a capsule around them, or a circle
/// around a lone one. [children] stay as they are: `IconButton`s,
/// `PopupMenuButton`s and `TextButton`s keep their tooltips, semantics,
/// keyboard focus and disabled grey, and stand [thickness] tall, a pressed
/// one alone on a platter, without a ripple, its corners concentric with the
/// pane's. A `PopupMenuButton`'s menu grows out of its button and returns
/// into it, as every menu on glass does. While all of them hide, as an `Obx`
/// hides its button, the pane is not drawn.
///
/// Without glass they stand as they are, in a row, or a column along
/// [direction].
class GlassButtonGroup extends StatefulWidget {
  const GlassButtonGroup({
    super.key,
    required this.children,
    this.direction = Axis.horizontal,
    this.glass,
  });

  /// How thick the pane is, and how long a button on it at least, as iOS
  /// 26's bar buttons are tall.
  static const double thickness = 44;

  /// How far a pressed button's platter stands in from the pane's edge.
  static const double platterInset = 2;

  final List<Widget> children;
  final Axis direction;

  /// Whether the buttons stand on glass: the 液态玻璃 switch when null.
  final bool? glass;

  /// The group [context] is in.
  static GlassButtonGroupState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<GlassButtonGroupState>();

  /// The pane's glass, for what draws the group elsewhere, as a page that
  /// grows out of its lone button.
  static LiquidGlassStyle styleOf(ColorScheme colorScheme) =>
      LiquidGlassStyle.regular(colorScheme);

  /// The pane's shadows.
  static List<BoxShadow> shadowsOf(ColorScheme colorScheme) =>
      floatingGlassShadows(colorScheme);

  @override
  State<GlassButtonGroup> createState() => GlassButtonGroupState();
}

class GlassButtonGroupState extends State<GlassButtonGroup> {
  bool _hidden = false;

  /// Whether it is glass.
  bool get glass => widget.glass ?? GlassSurfaces.installed;

  /// Whether it holds a lone button, which then is the whole group: what
  /// opens out of that button opens out of the whole pane, as out of a glass
  /// button of its own.
  bool get alone => widget.children.length == 1;

  /// The group, the pane's rect, while it is laid out.
  RenderBox? get box {
    if (!mounted) {
      return null;
    }
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Hides the whole group, pane and all, and lets taps through, as a page
  /// grown out of its lone button stands open over it.
  set hidden(bool value) {
    if (value != _hidden && mounted) {
      setState(() => _hidden = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = Flex(
      direction: widget.direction,
      mainAxisSize: MainAxisSize.min,
      children: widget.children,
    );
    if (!glass) {
      return buttons;
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onGlass = GlassSurfaces.withoutRipples(theme);
    final platter = onGlass.highlightColor;
    // A platter alone stands for a press, and for a mouse over it a fainter
    // one; a ring for the keyboard's focus.
    final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return platter;
      }
      if (states.contains(WidgetState.hovered)) {
        return platter.withValues(alpha: platter.a / 2);
      }
      return Colors.transparent;
    });
    final ring = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: colorScheme.primary, width: 2)
          : null,
    );
    const size = Size.square(GlassButtonGroup.thickness);
    const shape = WidgetStatePropertyAll<OutlinedBorder>(_PlatterBorder());
    final group = Stack(
      children: [
        // Sized by the buttons, so that it is empty, and not drawn, while
        // they all hide.
        Positioned.fill(
          child: LiquidGlass(
            style: GlassButtonGroup.styleOf(colorScheme),
            shadows: GlassButtonGroup.shadowsOf(colorScheme),
          ),
        ),
        Theme(
          data: onGlass.copyWith(
            iconButtonTheme: IconButtonThemeData(
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(size),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                splashFactory: NoSplash.splashFactory,
                overlayColor: overlay,
                side: ring,
                shape: shape,
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(size),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                splashFactory: NoSplash.splashFactory,
                overlayColor: overlay,
                side: ring,
                shape: shape,
              ),
            ),
          ),
          child: switch (widget.direction) {
            Axis.horizontal => SizedBox(
              height: GlassButtonGroup.thickness,
              child: buttons,
            ),
            // As wide as its widest button, a TextButton's label and all.
            Axis.vertical => ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: GlassButtonGroup.thickness,
              ),
              child: buttons,
            ),
          },
        ),
      ],
    );
    // Always there, so that hiding keeps the buttons' state.
    return IgnorePointer(
      ignoring: _hidden,
      child: Opacity(opacity: _hidden ? 0 : 1, child: group),
    );
  }
}

/// A stadium [GlassButtonGroup.platterInset] in from a button's edge: its
/// platter and focus ring, concentric with the pane around it.
class _PlatterBorder extends OutlinedBorder {
  const _PlatterBorder({super.side});

  StadiumBorder get _stadium => StadiumBorder(side: side);

  static Rect _inset(Rect rect) => rect.deflate(GlassButtonGroup.platterInset);

  @override
  EdgeInsetsGeometry get dimensions => _stadium.dimensions;

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      _PlatterBorder(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _PlatterBorder(side: side.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _stadium.getInnerPath(_inset(rect), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _stadium.getOuterPath(_inset(rect), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      _stadium.paint(canvas, _inset(rect), textDirection: textDirection);

  @override
  bool operator ==(Object other) =>
      other is _PlatterBorder && other.side == side;

  @override
  int get hashCode => side.hashCode;
}
