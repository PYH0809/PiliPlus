import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:material_ui/material_ui.dart';

/// A player whose controls popups over it hold up.
abstract interface class PopupControlsHolder {
  bool get controlsShown;
  void holdControls();
  void releaseControls();
}

/// Keeps the player's controls up while a popup over them is open, as a menu
/// out of their buttons or a dialog, and until it has gone back: the
/// controls go after it, not from under a menu still returning into its
/// button. A panel slid in, as 更多设置 or a sheet, is content of its own,
/// and the controls hide in their time under it as before.
class PlayerPopupObserver extends NavigatorObserver {
  PlayerPopupObserver({PopupControlsHolder? Function()? player})
    : _player = player ?? (() => PlPlayerController.instance);

  final PopupControlsHolder? Function() _player;
  final _held = <Route<dynamic>, PopupControlsHolder>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PopupRoute ||
        route is PublishRoute ||
        route is ModalBottomSheetRoute) {
      return;
    }
    final player = _player();
    final animation = route.animation;
    if (player == null || animation == null || !player.controlsShown) {
      return;
    }
    player.holdControls();
    _held[route] = player;
    void onStatus(AnimationStatus status) {
      if (status == .dismissed) {
        animation.removeStatusListener(onStatus);
        _release(route);
      }
    }

    animation.addStatusListener(onStatus);
  }

  // Gone without its animation back.
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _release(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _release(oldRoute);
  }

  void _release(Route<dynamic> route) => _held.remove(route)?.releaseControls();
}
