import 'dart:async';

import 'package:PiliPlus/pages/video/widgets/player_focus.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:material_ui/material_ui.dart';

class _MediaPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The player as PlayerFocus drives it with held arrow keys: a held back key
// steps the seek position back on the long-press timer, and its release
// seeks there, or a step back for a tap; a held forward key speeds up on
// the same timer, and its release slows down, or a step forward for a tap;
// a held volume key steps the volume on it.
class _Player implements PlPlayerController {
  @override
  bool isLive = false;

  @override
  final Player videoPlayerController = _MediaPlayer();

  @override
  Timer? longPressTimer;

  @override
  bool backKeyHeld = false;

  @override
  bool forwardKeyHeld = false;

  @override
  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }

  @override
  final position = RxInt(60);

  @override
  final isSeeking = false.obs;

  @override
  final seekPosition = RxInt(0);

  int steps = 0;
  final seeks = <int>[];

  @override
  void multiBackwardStart([_]) {
    steps++;
    final from = isSeeking.value ? seekPosition.value : position.value;
    isSeeking.value = true;
    seekPosition.value = from - 10;
  }

  @override
  void multiBackwardEnd() {
    if (isSeeking.value) {
      isSeeking.value = false;
      seeks.add(seekPosition.value);
    } else {
      // A tap, a step back from where playback is.
      seeks.add(position.value - 10);
    }
  }

  @override
  final fastForBackwardDuration = const Duration(seconds: 10);

  final forwards = <int>[];

  @override
  void onForward(Duration duration) => forwards.add(duration.inSeconds);

  @override
  final longPressStatus = false.obs;

  @override
  Future<void> setLongPressStatus(bool val) async {
    longPressStatus.value = val;
  }

  @override
  final double maxVolume = 1;

  @override
  final volume = RxDouble(0);

  @override
  Future<void> setVolume(double volume, {bool showIndicator = true}) async {
    this.volume.value = volume;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Player player;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    player = _Player();
    navigator = GlobalKey();
  });

  Future<void> pumpPlayer(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: PlayerFocus(
        plPlayerController: player,
        onSendDanmaku: () {},
        child: const SizedBox.expand(),
      ),
    ),
  );

  // As Enter opens the danmaku page over the player, taking the focus.
  Future<void> pushPage(WidgetTester tester) async {
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    // The page takes the focus as it is first built, a frame from now.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('a held back key steps back and seeks there as it comes up', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(player.steps, 2);
    expect(player.isSeeking.value, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(seconds: 1));
    expect(player.steps, 2);
    expect(player.isSeeking.value, isFalse);
    expect(player.seeks, [40]);
  });

  testWidgets('a tap of the back key steps back once', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(seconds: 1));
    expect(player.steps, 0);
    expect(player.seeks, [50]);
  });

  testWidgets('a back key held as a page opens over the player stops stepping '
      'and seeks nowhere', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    final steps = player.steps;

    await pushPage(tester);
    // The release goes to the page on top.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(seconds: 2));

    expect(player.steps, steps);
    expect(player.longPressTimer, isNull);
    expect(player.isSeeking.value, isFalse);
    expect(player.seeks, isEmpty);
  });

  testWidgets('a back key held till the player has its focus back comes up '
      'without a step back', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    final steps = player.steps;

    await pushPage(tester);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    // The release comes back to the player.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(seconds: 1));

    expect(player.steps, steps);
    expect(player.isSeeking.value, isFalse);
    expect(player.seeks, isEmpty);
  });

  testWidgets('losing focus with no back key held leaves a seek alone', (
    tester,
  ) async {
    await pumpPlayer(tester);
    // As a drag along the progress bar.
    player.isSeeking.value = true;

    await pushPage(tester);
    expect(player.isSeeking.value, isTrue);
  });

  testWidgets('a tap of the forward key steps forward once', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 1));
    expect(player.forwards, [10]);
    expect(player.longPressStatus.value, isFalse);
  });

  testWidgets('a held forward key speeds up and slows down as it comes up', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.longPressStatus.value, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(player.longPressStatus.value, isFalse);
    expect(player.forwards, isEmpty);
  });

  testWidgets('a forward key held till the player has its focus back comes '
      'up without a step forward', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));

    await pushPage(tester);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    // The release comes back to the player.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 1));

    expect(player.forwards, isEmpty);
    expect(player.longPressStatus.value, isFalse);
  });

  testWidgets('a forward key held into its speed-up as a page opens over the '
      'player slows down', (tester) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.longPressStatus.value, isTrue);

    await pushPage(tester);
    expect(player.longPressStatus.value, isFalse);
    // The release goes to the page on top.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 1));
    expect(player.forwards, isEmpty);
  });

  testWidgets('a volume key held as a page opens over the player stops', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 200));
    final volume = player.volume.value;

    await pushPage(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 1));

    expect(player.volume.value, volume);
    expect(player.longPressTimer, isNull);
  });
}
