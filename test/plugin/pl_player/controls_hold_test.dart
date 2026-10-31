import 'package:PiliPlus/plugin/pl_player/models/controls_hold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('not held, the controls hide when asked', () {
    final hold = ControlsHold();
    expect(hold.held, isFalse);
    expect(hold.hideNow(), isTrue);
  });

  test('a hide asked while a menu is open waits, and comes as it goes', () {
    final hold = ControlsHold()..hold();
    // Playing on after a quality picked in the menu.
    expect(hold.hideNow(), isFalse);
    expect(hold.release(), ControlsRelease.hide);
    expect(hold.held, isFalse);
  });

  test('a menu closed without a hide asked lets the controls hide in their '
      'usual time', () {
    final hold = ControlsHold()..hold();
    expect(hold.release(), ControlsRelease.hideLater);
  });

  test('showing the controls again calls off a hide asked before', () {
    final hold = ControlsHold()..hold();
    expect(hold.hideNow(), isFalse);
    hold.shown();
    expect(hold.release(), ControlsRelease.hideLater);
  });

  test('the controls go only once the last popup over them has', () {
    final hold = ControlsHold()
      ..hold()
      ..hold();
    expect(hold.hideNow(), isFalse);
    expect(hold.release(), isNull);
    expect(hold.held, isTrue);
    expect(hold.release(), ControlsRelease.hide);
  });

  test('a release with nothing held does nothing', () {
    expect(ControlsHold().release(), isNull);
  });
}
