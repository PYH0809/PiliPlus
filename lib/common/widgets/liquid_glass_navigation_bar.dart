import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

// The floating bar's metrics, as FloatingNavigationBar's.
const _kHeight = 64.0;
const _kItemWidth = 86.0;
const _kPadding = 4.0;

// After FlClash's lib/ui/navigation_dock.dart: a lifted lens grows this much a
// side, magnifies what it holds, and squashes as it stretches with its speed.
const _kLensGrowth = 8.0;
const _kLensMagnify = 0.16;
const _kJellyAspect = 1.4;
const _kJellyStretch = 0.07;
const _kMaxStretch = 0.15;

const _kMoveDuration = Duration(milliseconds: 700);
const _kLiftIn = Interval(0, 0.22, curve: Curves.easeOut);
const _kTravel = Interval(0.12, 0.78);
const _kSettle = Interval(0.74, 1, curve: Curves.easeIn);

class LiquidGlassNavigationDestination {
  const LiquidGlassNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

/// The floating navigation bar in liquid glass. Choosing a destination lifts
/// the selection into a clear lens that carries over to it and settles, as
/// iOS's tab bar does; the lens bends the bar and magnifies the destinations
/// under it. The glass bends what lies behind only under a [LiquidGlassHost],
/// and only frosts where Impeller is off.
class LiquidGlassNavigationBar extends StatefulWidget {
  const LiquidGlassNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.bottomPadding = 8.0,
  }) : assert(destinations.length >= 2),
       assert(0 <= selectedIndex && selectedIndex < destinations.length);

  final List<LiquidGlassNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double bottomPadding;

  @override
  State<LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<LiquidGlassNavigationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kMoveDuration,
    value: 1,
  );

  late double _from = widget.selectedIndex.toDouble();
  late double _to = _from;
  double _liftFrom = 0;

  double get _travel => _kTravel.transform(_controller.value);

  double get _position =>
      _from + (_to - _from) * Curves.easeInOutCubic.transform(_travel);

  double get _lift {
    final t = _controller.value;
    final rise = _liftFrom + (1 - _liftFrom) * _kLiftIn.transform(t);
    return rise.clamp(0.0, 1.0 - _kSettle.transform(t));
  }

  double get _stretch {
    final u = _travel;
    if (u <= 0 || u >= 1) {
      return 0;
    }
    // easeInOutCubic's speed, 3 at its peak.
    final speed = u < 0.5 ? 12 * u * u : 12 * (1 - u) * (1 - u);
    return (_kJellyStretch * speed / 3 * (_to - _from).abs()).clamp(
      0.0,
      _kMaxStretch,
    );
  }

  @override
  void didUpdateWidget(LiquidGlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.selectedIndex.toDouble();
    if (index == _to) {
      return;
    }
    _liftFrom = _controller.isAnimating ? _lift : 0;
    _from = _position;
    _to = index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final width = widget.destinations.length * _kItemWidth;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        widget.bottomPadding + padding.bottom,
      ),
      child: SizedBox(
        width: width,
        height: _kHeight,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _buildBar(context, width),
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context, double width) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final count = widget.destinations.length;
    final slot = (width - 2 * _kPadding) / count;
    final position = _position;
    final lift = _lift;
    final stretch = _stretch;

    final center = Offset(_kPadding + slot * (position + 0.5), _kHeight / 2);
    const restHeight = _kHeight - 2 * _kPadding;
    final rest = Rect.fromCenter(
      center: center,
      width: slot,
      height: restHeight,
    );
    final lens = Rect.fromCenter(
      center: center,
      width: (slot + 2 * _kLensGrowth * lift) * (1 + stretch),
      height:
          (restHeight + 2 * _kLensGrowth * lift) *
          (1 - stretch * _kJellyAspect),
    );
    final lensed = lift > 0;

    // FlClash's platter: the secondary hue at tone 90, or 4 in dark, which
    // sinks it below the bar.
    final hct = Hct.fromInt(colorScheme.secondary.toARGB32())
      ..tone = dark ? 4.0 : 90.0;
    final platter = Color(hct.toInt()).withValues(alpha: 0.85 * (1 - lift));

    final strength = dark ? 3.0 : 1.0;
    final barShadows = [
      BoxShadow(
        color: colorScheme.shadow.withValues(alpha: 0.08 * strength),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: colorScheme.shadow.withValues(alpha: 0.04 * strength),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ];

    final labelStyle = theme.textTheme.labelMedium!;
    final highlighted = position.round();

    Widget destinations({required bool inside}) => Padding(
      padding: const EdgeInsets.all(_kPadding),
      child: Row(
        children: [
          for (final (index, destination) in widget.destinations.indexed)
            Expanded(
              child: inside
                  ? Transform.scale(
                      scale: 1 + _kLensMagnify * lift,
                      child: _DestinationContent(
                        icon: destination.selectedIcon,
                        label: destination.label,
                        color: colorScheme.primary,
                        labelStyle: labelStyle,
                      ),
                    )
                  : _Destination(
                      label: destination.label,
                      selected: index == widget.selectedIndex,
                      onTap: () => widget.onDestinationSelected(index),
                      child: _DestinationContent(
                        icon: index == highlighted
                            ? destination.selectedIcon
                            : destination.icon,
                        label: destination.label,
                        color: index == highlighted
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        labelStyle: labelStyle,
                      ),
                    ),
            ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: LiquidGlass(
            style: LiquidGlassStyle.pill(colorScheme),
            shadows: barShadows,
          ),
        ),
        Positioned.fromRect(
          rect: rest,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: platter,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
        if (lensed)
          Positioned.fromRect(
            rect: lens,
            child: IgnorePointer(
              child: LiquidGlass(
                style: LiquidGlassStyle.lens(colorScheme).scale(lift),
                shadows: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: 0.055 * strength * lift,
                    ),
                    blurRadius: 5,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
        Positioned.fill(
          child: lensed
              ? ClipPath(
                  clipper: _LensClipper(lens, hole: true),
                  child: destinations(inside: false),
                )
              : destinations(inside: false),
        ),
        // What the lens holds of the destinations: a magnified copy in the
        // primary color, drawn offscreen so that its own pane warps only it.
        if (lensed)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ClipPath(
                  clipper: _LensClipper(lens),
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: destinations(inside: true)),
                      Positioned.fromRect(
                        rect: lens,
                        child: LiquidGlass(
                          style: LiquidGlassStyle.lensContent(
                            colorScheme,
                          ).scale(lift),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _DestinationContent extends StatelessWidget {
  const _DestinationContent({
    required this.icon,
    required this.label,
    required this.color,
    required this.labelStyle,
  });

  final Widget icon;
  final String label;
  final Color color;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconTheme.merge(
          data: IconThemeData(size: 24, color: color),
          child: icon,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle.copyWith(color: color),
        ),
      ],
    );
  }
}

class _LensClipper extends CustomClipper<Path> {
  const _LensClipper(this.lens, {this.hole = false});

  final Rect lens;

  /// Clips to everything but the lens.
  final bool hole;

  @override
  Path getClip(Size size) {
    final shape = Path()
      ..addRSuperellipse(
        RSuperellipse.fromRectAndRadius(
          lens,
          Radius.circular(lens.shortestSide / 2),
        ),
      );
    if (!hole) {
      return shape;
    }
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(_kLensGrowth * 3))
      ..addPath(shape, Offset.zero);
  }

  @override
  bool shouldReclip(_LensClipper oldClipper) =>
      oldClipper.lens != lens || oldClipper.hole != hole;
}
