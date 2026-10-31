/// What the player's controls do as the last popup holding them goes.
enum ControlsRelease {
  /// Hide at once: a hide was asked while they were held.
  hide,

  /// Hide in their usual time from now.
  hideLater,
}

/// Holds the player's controls up while popups out of them are open, as a
/// quality menu, and until each has gone back: the controls go after the
/// menu, not from under it. A hide asked meanwhile, as playing on after a
/// quality picked in the menu, waits for the menu.
class ControlsHold {
  int _count = 0;
  bool _hideAsked = false;

  bool get held => _count > 0;

  /// A popup opens over the controls.
  void hold() => _count++;

  /// Whether the controls may hide now; while held, the hide waits.
  bool hideNow() {
    if (!held) return true;
    _hideAsked = true;
    return false;
  }

  /// The controls show again, which calls off a hide asked before.
  void shown() => _hideAsked = false;

  /// A popup has gone back: once the last has, what the controls do.
  ControlsRelease? release() {
    if (_count == 0) return null;
    if (--_count > 0) return null;
    final hide = _hideAsked;
    _hideAsked = false;
    return hide ? .hide : .hideLater;
  }
}
