import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

// The floating bar's metrics, as FloatingNavigationBar's.
const _kHeight = 64.0;
const _kItemWidth = 86.0;
const _kPadding = 4.0;

// The rest are FlClash's, from lib/ui/navigation_dock.dart.

// A lifted lens grows this much a side and magnifies what it holds.
const _kLensGrowth = 8.0;
const _kLensMagnify = 0.16;

// The lens stretches with its speed and squashes as it brakes.
const _kJellyAspect = 1.4;
const _kJellySpeed = 3.0;
const _kJellyStretch = 0.2;
const _kJellyBrake = 25.0;
const _kJellySquash = 0.15;
const _kJellyRest = 3e-3;

// A press swells the bar by this share of it, at most this many dp.
const _kPressGrowth = 1 / 8;
const _kMaxPressGrowth = 16.0;

// A lens let go drops once it has risen this far and is this near its place.
const _kLiftSnap = 0.975;
const _kLiftRelease = 0.04;

// Dragging past either end gives way like a rubber band, and stretches the
// bar toward the finger.
const _kOverdrag = 0.35;
const _kPullLimit = 7 / 32;
const _kPullStretch = 0.5;
const _kFlingProjection = Duration(milliseconds: 100);

// The finger lights the bar, and the light spreads as it fades on release.
const _kGlowReach = 28.0;
const _kGlowGrowth = 3.0;
const _kGlowPeak = 0.06;
const _kGlowWash = 0.7;

final _trackSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 120),
);
final _pressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 311,
  ratio: 0.593,
);
final _followSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 1024,
  ratio: 0.9,
);
// How fast a pressed lens lifts, and how fast it travels to the destination
// tapped or let go over.
final _liftSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 250),
);
final _travelSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 400),
  bounce: 0.15,
);
final _jellySpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 100,
  ratio: 0.4,
);
final _glowInSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 100),
);
final _glowOutSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 500),
);

double _rubberBand(double overshoot, double limit) {
  final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
  return limit * pull * overshoot.sign;
}

double _saturate(double value) => 1 - 2 / (math.exp(2 * value) + 1);

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

/// The floating navigation bar in liquid glass, after iOS's tab bar and
/// FlClash's navigation dock. A press swells the bar and lifts the selection
/// into a clear lens under the finger; dragging slides the lens across the
/// bar, selecting where it is let go, and stretches the bar past either end.
/// The lens bends the bar and magnifies the destinations under it. The glass
/// bends what lies behind only under a [LiquidGlassHost], and only frosts
/// where Impeller is off.
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
    with TickerProviderStateMixin {
  late final _lens = GlassSpring(this, widget.selectedIndex.toDouble());
  late final _lift = GlassSpring(this, 0);
  late final _swell = GlassSpring(this, 0);
  late final _pull = GlassSpring(this, 0);
  late final _jelly = GlassSpring(this, 0, rest: _kJellyRest);
  late final _glow = GlassSpring(this, 0);
  late final _glowSpread = GlassSpring(this, 0);
  late final Listenable _barMotion = Listenable.merge([_swell, _pull]);
  late final Listenable _motion = Listenable.merge([_lens, _lift, _jelly]);
  final _touchGlow = ValueNotifier(LiquidGlassGlow.none);
  Offset _glowAt = Offset.zero;

  int? _pointer;
  int? _pressedIndex;
  double _pressX = 0;
  bool _dragging = false;
  bool _dropping = false;
  VelocityTracker? _tracker;
  int? _focusedIndex;

  int get _lastIndex => widget.destinations.length - 1;

  // As wide as the destinations ask, unless the screen is narrower; set as the
  // bar lays out.
  late double _width;

  double get _pitch => (_width - 2 * _kPadding) / widget.destinations.length;

  @override
  void initState() {
    super.initState();
    _lens
      ..addListener(_wobble)
      ..addListener(_dropLift);
    _lift.addListener(_dropLift);
    _glow.addListener(_shine);
    _glowSpread.addListener(_shine);
  }

  @override
  void didUpdateWidget(LiquidGlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedIndex.toDouble();
    if (_pressedIndex == null && _lens.target != selected) {
      _springTo(_lens, selected, _travelSpring);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    _lift.dispose();
    _swell.dispose();
    _pull.dispose();
    _jelly.dispose();
    _glow.dispose();
    _glowSpread.dispose();
    _touchGlow.dispose();
    super.dispose();
  }

  void _springTo(
    GlassSpring spring,
    double target,
    SpringDescription description,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      spring.jumpTo(target);
    } else {
      spring.springTo(target, description);
    }
  }

  void _wobble() {
    final velocity = _lens.velocity;
    final braking = math.max(0.0, -_lens.acceleration * velocity.sign);
    final target =
        _kJellyStretch * _saturate(velocity.abs() / _kJellySpeed) -
        _kJellySquash * _saturate(braking / _kJellyBrake);
    if (target != _jelly.target) {
      _jelly.springTo(target, _jellySpring);
    }
  }

  void _shine() {
    final glow = _glow.value;
    _touchGlow.value = LiquidGlassGlow(
      center: _glowAt,
      reach: _kGlowReach * (1 + _kGlowGrowth * _glowSpread.value),
      strength: _kGlowPeak * glow * glow,
      wash: _kGlowWash,
    );
  }

  // As UIKit, the lens stays lifted until it has risen all the way and
  // arrived.
  void _dropLift() {
    if (!_dropping || _pointer != null || _lift.value < _kLiftSnap) {
      return;
    }
    if ((_lens.target - _lens.value).abs() > _kLiftRelease) {
      return;
    }
    _dropping = false;
    _springTo(_lift, 0, _liftSpring);
  }

  double _positionAt(Offset localPosition) {
    final position = (localPosition.dx - _kPadding) / _pitch - 0.5;
    if (position < 0) {
      return _rubberBand(position, _kOverdrag);
    }
    if (position > _lastIndex) {
      return _lastIndex + _rubberBand(position - _lastIndex, _kOverdrag);
    }
    return position;
  }

  int _indexAt(double position) => position.round().clamp(0, _lastIndex);

  void _highlightFocus(int index, bool highlight) {
    if (highlight) {
      setState(() => _focusedIndex = index);
    } else if (_focusedIndex == index) {
      setState(() => _focusedIndex = null);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _springTo(_swell, 1, _pressSpring);
    _glowAt = event.localPosition;
    _glowSpread.jumpTo(0);
    _springTo(_glow, 1, _glowInSpring);

    final index = _indexAt(_positionAt(event.localPosition));
    _pressedIndex = index;
    _pressX = event.localPosition.dx;
    _dragging = false;
    _dropping = false;
    _springTo(_lift, 1, _liftSpring);
    _springTo(_lens, index.toDouble(), _travelSpring);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _pressedIndex == null) {
      return;
    }
    final position = event.localPosition;
    _tracker?.addPosition(event.timeStamp, position);
    _glowAt = position;
    _shine();
    if (!_dragging) {
      if ((position.dx - _pressX).abs() < kTouchSlop) {
        return;
      }
      _dragging = true;
    }
    final overshoot = position.dx - position.dx.clamp(0.0, _width);
    _springTo(
      _pull,
      _rubberBand(overshoot, _kHeight * _kPullLimit),
      _trackSpring,
    );
    final lens = _positionAt(position);
    _springTo(_lens, lens, _followSpring);
    final index = _indexAt(lens);
    if (index != _pressedIndex) {
      _pressedIndex = index;
      feedBack();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    final tracker = _tracker;
    _tracker = null;
    if (event is PointerUpEvent && tracker != null) {
      _fling(tracker.getVelocity().pixelsPerSecond.dx);
    }
    _release(commit: event is PointerUpEvent);
    _springTo(_glow, 0, _glowOutSpring);
    _springTo(_glowSpread, 1, _glowOutSpring);
    _springTo(_pull, 0, _pressSpring);
    _springTo(_swell, 0, _pressSpring);
  }

  /// Carries a drag let go mid-flick on to the next destination, at most one
  /// past the one under the finger.
  void _fling(double velocityX) {
    final pressed = _pressedIndex;
    if (!_dragging || pressed == null) {
      return;
    }
    final lead =
        velocityX /
        _pitch *
        _kFlingProjection.inMicroseconds /
        Duration.microsecondsPerSecond;
    final index = (_lens.target + lead)
        .round()
        .clamp(pressed - 1, pressed + 1)
        .clamp(0, _lastIndex);
    if (index != pressed) {
      _pressedIndex = index;
      feedBack();
    }
  }

  void _release({required bool commit}) {
    final index = _pressedIndex;
    if (index == null) {
      return;
    }
    final dragged = _dragging;
    _pressedIndex = null;
    _dragging = false;
    _dropping = true;
    final target = commit ? index : widget.selectedIndex;
    _springTo(_lens, target.toDouble(), _travelSpring);
    _dropLift();
    // A tap on the current destination still reports it, as the other bars
    // do, so that it scrolls to the top or refreshes; a drag let go there
    // does not.
    if (commit && (!dragged || index != widget.selectedIndex)) {
      widget.onDestinationSelected(index);
    }
  }

  Matrix4? _pressTransform(Size size) {
    final swell =
        1 +
        _swell.value *
            math.min(_kPressGrowth * 2, _kMaxPressGrowth / size.longestSide);
    final pull = _pull.value;
    if (swell == 1 && pull == 0) {
      return null;
    }
    final scaleX = swell * (1 + pull.abs() / size.width * _kPullStretch);
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scaleX, swell, 1)..setTranslationRaw(
      center.dx * (1 - scaleX) + pull,
      center.dy * (1 - swell),
      0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        widget.bottomPadding + padding.bottom,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = math.min(
            widget.destinations.length * _kItemWidth,
            constraints.maxWidth,
          );
          final size = Size(_width, _kHeight);
          return SizedBox.fromSize(
            size: size,
            // Raw pointers rather than recognizers: a drag has nothing to win
            // the arena from, and a tap waiting on one would lift the lens
            // late.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerEnd,
              onPointerCancel: _handlePointerEnd,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedBuilder(
                  animation: _barMotion,
                  builder: (context, child) {
                    final transform = _pressTransform(size);
                    return transform == null
                        ? child!
                        : Transform(transform: transform, child: child);
                  },
                  child: AnimatedBuilder(
                    animation: _motion,
                    builder: (context, _) => _buildBar(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final pitch = _pitch;
    final position = _lens.value;
    final lift = _lift.value.clamp(0.0, 1.0);
    final stretch = _jelly.value;

    final center = Offset(_kPadding + pitch * (position + 0.5), _kHeight / 2);
    const restHeight = _kHeight - 2 * _kPadding;
    final rest = Rect.fromCenter(
      center: center,
      width: pitch,
      height: restHeight,
    );
    final growth = 2 * _kLensGrowth * lift;
    final lens = Rect.fromCenter(
      center: center,
      width: (pitch + growth) * (1 + stretch),
      height: (restHeight + growth) * (1 - stretch * _kJellyAspect),
    );
    final lensed = lift > 0;

    final platter = glassPlatterColor(colorScheme);
    final restPlatter = platter.withValues(alpha: platter.a * (1 - lift));

    final strength = dark ? 3.0 : 1.0;
    final barShadows = floatingGlassShadows(colorScheme);

    final labelStyle = theme.textTheme.labelMedium!;
    final highlighted = _indexAt(position);

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
                  : FocusableActionDetector(
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (_) {
                            widget.onDestinationSelected(index);
                            return null;
                          },
                        ),
                      },
                      onShowFocusHighlight: (highlight) =>
                          _highlightFocus(index, highlight),
                      child: Semantics(
                        container: true,
                        button: true,
                        selected: index == widget.selectedIndex,
                        label: destination.label,
                        excludeSemantics: true,
                        onTap: () => widget.onDestinationSelected(index),
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: index == _focusedIndex
                              ? ShapeDecoration(
                                  shape: StadiumBorder(
                                    side: BorderSide(
                                      color: colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                )
                              : const BoxDecoration(),
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
                    ),
            ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ValueListenableBuilder(
            valueListenable: _touchGlow,
            builder: (context, glow, _) => LiquidGlass(
              style: LiquidGlassStyle.pill(colorScheme),
              shadows: barShadows,
              glow: glow,
            ),
          ),
        ),
        Positioned.fromRect(
          rect: rest,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: restPlatter,
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
        // Kept when nothing is lensed, so that a lens lifting leaves the
        // destinations, and the focus they hold, where they are.
        Positioned.fill(
          child: ClipPath(
            clipper: lensed ? _LensClipper(lens, hole: true) : null,
            clipBehavior: lensed ? Clip.antiAlias : Clip.none,
            child: destinations(inside: false),
          ),
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
