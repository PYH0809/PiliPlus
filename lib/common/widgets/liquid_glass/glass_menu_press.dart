// After FlClash's popup press (https://github.com/chen08209/FlClash,
// lib/ui/popup.dart, GPL-3.0).

import 'dart:async';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Opens a popup menu on its button's pointer down, as iOS menus do, and
/// carries the press on into it, so the finger can slide on into the menu and
/// let go on an item. In a scroll view it waits a moment first, so that a
/// drag scrolls instead. The button is the menu's [GlassMenuSource], so the
/// menu takes it in as it opens and gives it back as it returns.
class GlassMenuPress extends StatefulWidget {
  const GlassMenuPress({super.key, required this.open, required this.child});

  /// Opens the menu.
  final VoidCallback open;
  final Widget child;

  @override
  State<GlassMenuPress> createState() => _GlassMenuPressState();
}

class _GlassMenuPressState extends State<GlassMenuPress> {
  final _source = GlobalKey<GlassMenuSourceState>();
  int? _pointer;
  Offset _origin = Offset.zero;
  bool _moved = false;

  void _handlePress(PointerDownEvent event) {
    _pointer = event.pointer;
    _origin = event.position;
    _moved = false;
    _source.currentState?.arm();
    widget.open();
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final slop = computeHitSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
    _moved = _moved || (event.position - _origin).distance > slop;
    if (_moved) {
      GlassMenuMorph.track(event.position);
    }
  }

  // A tap leaves the menu open; a press slid on into it picks what it ends on.
  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    if (_moved) {
      GlassMenuMorph.release(event.position);
    }
  }

  void _handleCancel() {
    if (_pointer == null) {
      return;
    }
    _pointer = null;
    GlassMenuMorph.track(null);
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      excludeFromSemantics: true,
      gestures: {
        _MenuPressRecognizer:
            GestureRecognizerFactoryWithHandlers<_MenuPressRecognizer>(
              () => _MenuPressRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..delay = Scrollable.maybeOf(context) == null
                    ? Duration.zero
                    : kPressTimeout
                ..onPress = _handlePress
                ..onMove = _handleMove
                ..onUp = _handleUp
                ..onCancel = _handleCancel,
            ),
      },
      child: GlassMenuSource(key: _source, child: widget.child),
    );
  }
}

/// Claims a press on the button, so that its own tap and tooltip stand down,
/// once [delay] has passed without the pointer moving off.
class _MenuPressRecognizer extends OneSequenceGestureRecognizer {
  _MenuPressRecognizer({super.debugOwner});

  Duration delay = Duration.zero;
  ValueSetter<PointerDownEvent>? onPress;
  ValueSetter<PointerMoveEvent>? onMove;
  ValueSetter<PointerUpEvent>? onUp;
  VoidCallback? onCancel;

  PointerDownEvent? _down;
  Timer? _timer;
  bool _pressed = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _down == null &&
      event.buttons == kPrimaryButton &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event;
    _pressed = false;
    startTrackingPointer(event.pointer, event.transform);
    if (delay == Duration.zero) {
      _press();
    } else {
      _timer = Timer(delay, _press);
    }
  }

  void _press() {
    _timer?.cancel();
    _timer = null;
    final down = _down;
    if (down == null || _pressed) {
      return;
    }
    _pressed = true;
    resolve(GestureDisposition.accepted);
    onPress?.call(down);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (down == null) {
      return;
    }
    if (event is PointerMoveEvent) {
      if (_pressed) {
        onMove?.call(event);
      } else if ((event.position - down.position).distance >
          computeHitSlop(event.kind, gestureSettings)) {
        resolve(GestureDisposition.rejected);
        _reset(event.pointer);
      }
    } else if (event is PointerUpEvent) {
      _press();
      onUp?.call(event);
      _reset(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_pressed) {
        onCancel?.call();
      } else {
        resolve(GestureDisposition.rejected);
      }
      _reset(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    final pressed = _pressed;
    _reset(pointer);
    if (pressed) {
      onCancel?.call();
    }
  }

  void _reset(int pointer) {
    _timer?.cancel();
    _timer = null;
    _down = null;
    _pressed = false;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  String get debugDescription => 'menu press';
}
