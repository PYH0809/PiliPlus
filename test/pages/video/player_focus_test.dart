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
// seeks there; a held volume key steps the volume on the same timer.
class _Player implements PlPlayerController {
  @override
  bool isLive = false;

  @override
  final Player videoPlayerController = _MediaPlayer();

  @override
  Timer? longPressTimer;

  @override
  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }

  @override
  final isSeeking = false.obs;

  @override
  final seekPosition = RxInt(60);

  int steps = 0;
  final seeks = <int>[];

  @override
  void multiBackwardStart([_]) {
    steps++;
    isSeeking.value = true;
    seekPosition.value -= 10;
  }

  @override
  void multiBackwardEnd() {
    if (isSeeking.value) {
      isSeeking.value = false;
      seeks.add(seekPosition.value);
    }
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

  testWidgets('losing focus with no back key held leaves a seek alone', (
    tester,
  ) async {
    await pumpPlayer(tester);
    // As a drag along the progress bar.
    player.isSeeking.value = true;

    await pushPage(tester);
    expect(player.isSeeking.value, isTrue);
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
