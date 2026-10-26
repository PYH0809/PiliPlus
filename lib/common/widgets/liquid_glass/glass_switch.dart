// After FlClash's CommonSwitch (https://github.com/chen08209/FlClash,
// lib/ui/switch.dart, GPL-3.0).

import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// The M3 switch's track and thumb, drawn here so no ripple or overlay rings
/// it, and filled solid while off rather than outlined. A press lifts the
/// thumb out past the track, white as iOS's solid thumb is; on liquid glass
/// the lifted thumb turns into a clear lens over the track, as iOS's does.
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const trackWidth = 52.0;
  static const trackHeight = 32.0;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch>
    with TickerProviderStateMixin {
  // M3's layout: 4 dp either side of the track, as tall as a tap target.
  static const _inset = 4.0;
  static const _thumb = 24.0;
  static const _midThumb = Size(34, 22);
  static const _heldThumb = 40.0;
  static const _heldStretch = Offset(10, -2);
  static const _toggleDuration = Duration(milliseconds: 300);
  static const _pressDuration = Duration(milliseconds: 150);
  static const _tapLift = Duration(milliseconds: 200);

  late final _toggle = AnimationController(
    vsync: this,
    duration: _toggleDuration,
    value: widget.value ? 1 : 0,
  );
  late final _position = CurvedAnimation(
    parent: _toggle,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeOutBack.flipped,
  );
  late final _pressController = AnimationController(
    vsync: this,
    duration: _pressDuration,
  );
  late final _press = CurvedAnimation(
    parent: _pressController,
    curve: Curves.easeOutCubic,
  );
  late final _motion = Listenable.merge([_position, _press]);

  Timer? _tapLiftTimer;
  var _dragging = false;
  var _focused = false;

  Duration _motionDuration(Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _toggle.duration = _motionDuration(_toggleDuration);
    _pressController.duration = _motionDuration(_pressDuration);
  }

  @override
  void didUpdateWidget(GlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (_toggle.isDismissed || _toggle.isCompleted) {
        _position
          ..curve = Curves.easeOutBack
          ..reverseCurve = Curves.easeOutBack.flipped;
      }
      // A drag hands over its flip with the thumb already past halfway.
      final across = (_toggle.value - (widget.value ? 1 : 0)).abs() > 0.5;
      if (across && widget.onChanged != null) {
        _liftAcross();
      }
      _settle();
    }
  }

  @override
  void dispose() {
    _tapLiftTimer?.cancel();
    _position.dispose();
    _press.dispose();
    _toggle.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _settle() => widget.value ? _toggle.forward() : _toggle.reverse();

  void _flip() => widget.onChanged?.call(!widget.value);

  void _handlePress() {
    _tapLiftTimer?.cancel();
    _pressController.forward();
  }

  void _liftAcross() {
    _handlePress();
    _tapLiftTimer = Timer(
      _motionDuration(_tapLift),
      _pressController.reverse,
    );
  }

  void _handleDragStart() {
    _handlePress();
    _dragging = true;
    _position
      ..curve = Curves.linear
      ..reverseCurve = Curves.linear;
  }

  void _handleDrag(double dx) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _toggle.value +=
        (rtl ? -dx : dx) / (GlassSwitch.trackWidth - GlassSwitch.trackHeight);
  }

  void _handleRelease() {
    if (!_dragging) {
      _flip();
      _liftAcross();
      return;
    }
    _pressController.reverse();
    _dragging = false;
    if (_toggle.value >= 0.5 == widget.value) {
      _settle();
      return;
    }
    _flip();
    // The flipped value arrives with the next build, if the owner takes it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _settle();
      }
    });
  }

  void _handleCancel() {
    _pressController.reverse();
    if (_dragging) {
      _dragging = false;
      _settle();
    }
  }

  Rect _thumbIn(Rect track, bool rtl) {
    final on = _toggle.value;
    final stretch = math.sin(math.pi * on.clamp(0.0, 1.0));
    final size = Size.lerp(
      Size.lerp(const Size.square(_thumb), _midThumb, stretch),
      const Size.square(_heldThumb) + _heldStretch * stretch,
      _press.value,
    )!;
    final along =
        track.height / 2 + (track.width - track.height) * _position.value;
    return Rect.fromCenter(
      center: Offset(
        rtl ? track.right - along : track.left + along,
        track.center.dy,
      ),
      width: size.width,
      height: size.height,
    );
  }

  Widget _buildParts(BuildContext context, Size size) {
    final colorScheme = ColorScheme.of(context);
    final enabled = widget.onChanged != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final on = _toggle.value.clamp(0.0, 1.0);
    final lift = _press.value;
    final track = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: GlassSwitch.trackWidth,
      height: GlassSwitch.trackHeight,
    );
    final trackColor = enabled
        ? Color.lerp(
            colorScheme.surfaceContainerHighest,
            colorScheme.primary,
            on,
          )
        : Color.lerp(
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
            colorScheme.onSurface.withValues(alpha: 0.12),
            on,
          );
    final thumbColor = enabled
        ? Color.lerp(colorScheme.outline, colorScheme.onPrimary, on)!
        : Color.lerp(
            colorScheme.onSurface.withValues(alpha: 0.38),
            colorScheme.surface,
            on,
          )!;
    final shadows = [
      if (lift > 0)
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.2 * lift),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
    ];
    final lens = LiquidGlassScope.of(context) && lift > 0;
    final thumbFill = lens
        ? thumbColor.withValues(alpha: thumbColor.a * (1 - lift))
        : Color.lerp(thumbColor, Colors.white, lift)!;
    final thumb = DecoratedBox(
      decoration: ShapeDecoration(
        color: thumbFill,
        shape: const StadiumBorder(),
        shadows: lens ? null : shadows,
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: track,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: trackColor,
              shape: const StadiumBorder(),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: _thumbIn(track, rtl),
          child: lens
              ? LiquidGlass(
                  style: LiquidGlassStyle.lens(colorScheme).scale(lift),
                  shadows: shadows,
                  child: thumb,
                )
              : thumb,
        ),
        if (_focused)
          Positioned.fromRect(
            rect: track,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final size = Size(
      GlassSwitch.trackWidth + _inset * 2,
      switch (Theme.of(context).materialTapTargetSize) {
        MaterialTapTargetSize.padded => kMinInteractiveDimension,
        MaterialTapTargetSize.shrinkWrap => kMinInteractiveDimension - 8,
      },
    );
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      onTap: enabled ? _flip : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _flip(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onHorizontalDragStart: enabled ? (_) => _handleDragStart() : null,
          onHorizontalDragUpdate: enabled
              ? (details) => _handleDrag(details.primaryDelta!)
              : null,
          onHorizontalDragEnd: enabled ? (_) => _handleRelease() : null,
          onHorizontalDragCancel: enabled ? _handleCancel : null,
          child: _buildTapTarget(
            enabled: enabled,
            child: SizedBox.fromSize(
              size: size,
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => _buildParts(context, size),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Taps go through an invisible [InkResponse] because an InkWell around the
  /// switch skips its own press ink while one inside it is pressed.
  Widget _buildTapTarget({required bool enabled, required Widget child}) {
    if (!enabled) {
      return child;
    }
    if (Material.maybeOf(context) == null) {
      return GestureDetector(
        excludeFromSemantics: true,
        onTapDown: (_) => _handlePress(),
        onTap: _handleRelease,
        onTapCancel: _handleCancel,
        child: child,
      );
    }
    return InkResponse(
      onTapDown: (_) => _handlePress(),
      onTap: _handleRelease,
      onTapCancel: _handleCancel,
      excludeFromSemantics: true,
      canRequestFocus: false,
      enableFeedback: false,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: child,
    );
  }
}
