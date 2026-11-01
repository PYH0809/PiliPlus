import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:flutter/gestures.dart'
    show
        Offset,
        GestureRecognizer,
        PointerDownEvent,
        PointerEvent,
        HorizontalDragGestureRecognizer,
        DeviceGestureSettings,
        PointerDeviceKind,
        kPrecisePointerHitSlop,
        kTouchSlop,
        PointerPanZoomStartEvent;

mixin InitialPositionMixin on GestureRecognizer {
  Offset? _initialPosition;
  Offset? get initialPosition => _initialPosition;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _initialPosition = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _initialPosition = event.position;
    super.addAllowedPointerPanZoom(event);
  }
}

class CustomHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer
    with InitialPositionMixin {
  CustomHorizontalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  @override
  DeviceGestureSettings get gestureSettings => _gestureSettings;
  final _gestureSettings = DeviceGestureSettings(touchSlop: touchSlopH);

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return _computeHitSlop(
      globalDistanceMoved.abs(),
      gestureSettings,
      pointerDeviceKind,
      _initialPosition,
      lastPosition.global,
    );
  }

  @override
  Type get runtimeType => HorizontalDragGestureRecognizer;
}

/// For a [TabBarView]: on its first or last tab it leaves a drag out past
/// that tab, so a [TabBarView] around it takes the drag and turns its own tab.
class TabBarViewDragGestureRecognizer
    extends CustomHorizontalDragGestureRecognizer {
  TabBarViewDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    required this.canTurn,
    this.isDxAllowed,
  });

  /// Whether there is a tab to turn to: the next one if `forward`, else the
  /// one before.
  final bool Function(bool forward) canTurn;

  /// Where across it a drag may start, if not anywhere: a panel that closes
  /// on a swipe from its edges keeps them for that.
  final bool Function(double dx)? isDxAllowed;

  @override
  bool isPointerAllowed(PointerEvent event) {
    return (isDxAllowed?.call(event.localPosition.dx) ?? true) &&
        super.isPointerAllowed(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind,
          deviceTouchSlop,
        ) &&
        // A finger moving left brings the next tab in.
        canTurn(globalDistanceMoved < 0);
  }
}

double touchSlopH = Pref.touchSlopH;

bool _computeHitSlop(
  double globalDistanceMoved,
  DeviceGestureSettings settings,
  PointerDeviceKind kind,
  Offset? initialPosition,
  Offset lastPosition,
) {
  switch (kind) {
    case .mouse:
      return globalDistanceMoved > kPrecisePointerHitSlop;
    case .stylus:
    case .invertedStylus:
    case .unknown:
    case .touch:
      return globalDistanceMoved > settings.touchSlop! &&
          _calcAngle(initialPosition!, lastPosition);
    case .trackpad:
      return globalDistanceMoved > settings.touchSlop! &&
          _calcAngle(initialPosition!, lastPosition);
  }
}

bool _calcAngle(Offset initialPosition, Offset lastPosition) {
  final offset = lastPosition - initialPosition;
  return offset.dx.abs() > offset.dy.abs() * 3;
}

final deviceTouchSlop = _calcDeviceTouchSlop();

double _calcDeviceTouchSlop() {
  final view = PlatformDispatcher.instance.views.first;
  final physicalTouchSlop = view.gestureSettings.physicalTouchSlop;
  return physicalTouchSlop == null
      ? kTouchSlop
      : physicalTouchSlop / view.devicePixelRatio;
}
