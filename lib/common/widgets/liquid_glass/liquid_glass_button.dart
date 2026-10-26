import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

// As FlClash's ElasticPress: a press swells a pane by an eighth of its size a
// side, at most 16 dp across, and lights it from the finger.
const _kPressGrowth = 1 / 8;
const _kMaxPressGrowth = 16.0;
const _kGlowReach = 28.0;
const _kGlowGrowth = 3.0;
const _kGlowPeak = 0.06;
const _kGlowWash = 0.7;

final _pressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 311,
  ratio: 0.593,
);
final _glowInSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 100),
);
final _glowOutSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 500),
);

/// A pressable pane of liquid glass behind [child]: a pill unless
/// [borderRadius] rounds it otherwise. A press swells it and lights it from
/// the finger, and a tap calls [onTap].
class LiquidGlassButton extends StatefulWidget {
  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.styleOf = LiquidGlassStyle.regular,
    this.shadows = const [],
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final LiquidGlassStyle Function(ColorScheme colorScheme) styleOf;
  final List<BoxShadow> shadows;
  final String? tooltip;

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with TickerProviderStateMixin {
  late final _swell = GlassSpring(this, 0);
  late final _glow = GlassSpring(this, 0);
  late final _glowSpread = GlassSpring(this, 0);
  final _touchGlow = ValueNotifier(LiquidGlassGlow.none);
  Offset _glowAt = Offset.zero;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    _glow.addListener(_shine);
    _glowSpread.addListener(_shine);
  }

  @override
  void dispose() {
    _swell.dispose();
    _glow.dispose();
    _glowSpread.dispose();
    _touchGlow.dispose();
    super.dispose();
  }

  void _springTo(GlassSpring spring, double target, SpringDescription to) {
    if (MediaQuery.disableAnimationsOf(context)) {
      spring.jumpTo(target);
    } else {
      spring.springTo(target, to);
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

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null ||
        widget.onTap == null ||
        event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _glowAt = event.localPosition;
    _glowSpread.jumpTo(0);
    _springTo(_glow, 1, _glowInSpring);
    _springTo(_swell, 1, _pressSpring);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer == _pointer) {
      _glowAt = event.localPosition;
      _shine();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _springTo(_glow, 0, _glowOutSpring);
    _springTo(_glowSpread, 1, _glowOutSpring);
    _springTo(_swell, 0, _pressSpring);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    Widget button = Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.biggest.longestSide;
            final growth = side.isFinite && side > 0
                ? math.min(_kPressGrowth * 2, _kMaxPressGrowth / side)
                : 0.0;
            return AnimatedBuilder(
              animation: _swell,
              builder: (context, child) {
                final swell = _swell.value;
                if (swell == 0 || growth == 0) {
                  return child!;
                }
                return Transform.scale(
                  scale: 1 + growth * swell,
                  child: child,
                );
              },
              child: ValueListenableBuilder(
                valueListenable: _touchGlow,
                builder: (context, glow, child) => LiquidGlass(
                  style: widget.styleOf(colorScheme),
                  borderRadius: widget.borderRadius,
                  shadows: widget.shadows,
                  glow: glow,
                  child: child,
                ),
                child: widget.child,
              ),
            );
          },
        ),
      ),
    );
    if (widget.onTap != null) {
      button = MouseRegion(cursor: SystemMouseCursors.click, child: button);
    }
    if (widget.tooltip case final tooltip?) {
      button = Tooltip(message: tooltip, child: button);
    }
    return Semantics(
      button: widget.onTap != null,
      label: widget.tooltip,
      child: button,
    );
  }
}
