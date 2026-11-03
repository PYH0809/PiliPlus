import 'package:PiliPlus/pages/video/widgets/first_frame.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// The shared player, as much of it as the watch reads: it goes through its
/// position listeners as [PlPlayerController] does, over the set itself.
class _Player implements PlPlayerController {
  final _positionListeners = <ValueChanged<Duration>>{};

  @override
  int? cid;

  @override
  final Rx<DataStatus> dataStatus = Rx(DataStatus.none);

  @override
  PlayerStatus playerStatus = PlayerStatus.paused;

  @override
  Null get videoController => null;

  @override
  void addPositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.add(listener);

  @override
  void removePositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.remove(listener);

  void playTo(Duration position) {
    for (final listener in _positionListeners) {
      listener(position);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('shows once this video plays on, leaving the player be', () async {
    final player = _Player()..cid = 1;
    var shown = 0;
    // Another listener after it, which the player must still reach.
    var reached = 0;
    watchFirstFrame(player, cid: () => 2, shown: () => shown++);

    // The page below's video still loaded and playing.
    player
      ..dataStatus.value = DataStatus.loaded
      ..playerStatus = PlayerStatus.playing;
    await Future<void>.delayed(Duration.zero);
    player.playTo(const Duration(seconds: 3));
    expect(shown, 0);

    // This page's video.
    player
      ..cid = 2
      ..dataStatus.value = DataStatus.loading
      ..dataStatus.value = DataStatus.loaded;
    await Future<void>.delayed(Duration.zero);
    player
      ..addPositionListener((_) => reached++)
      ..playTo(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(shown, 1);
    expect(reached, 1);
    expect(player._positionListeners, hasLength(1));

    player.playTo(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(shown, 1);
  });

  test('a page opened over it, taking the player, does not count', () async {
    final player = _Player()..cid = 2;
    var shown = 0;
    watchFirstFrame(player, cid: () => 2, shown: () => shown++);
    player.dataStatus.value = DataStatus.loaded;
    await Future<void>.delayed(Duration.zero);

    // A related video opened over the page plays on the same player.
    player
      ..cid = 3
      ..dataStatus.value = DataStatus.loading
      ..dataStatus.value = DataStatus.loaded
      ..playerStatus = PlayerStatus.playing
      ..playTo(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(shown, 0);
  });

  test('a part picked before the first frame is watched instead', () async {
    final player = _Player()..cid = 2;
    var cid = 2;
    var shown = 0;
    watchFirstFrame(player, cid: () => cid, shown: () => shown++);
    player.dataStatus.value = DataStatus.loaded;
    await Future<void>.delayed(Duration.zero);

    cid = 4;
    player
      ..cid = 4
      ..dataStatus.value = DataStatus.loading
      ..dataStatus.value = DataStatus.loaded
      ..playerStatus = PlayerStatus.playing
      ..playTo(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(shown, 1);
  });

  test('shows once the video fails to load', () async {
    final player = _Player()..cid = 2;
    var shown = 0;
    watchFirstFrame(player, cid: () => 2, shown: () => shown++);
    player.dataStatus.value = DataStatus.error;
    await Future<void>.delayed(Duration.zero);
    expect(shown, 1);
  });

  test('stops watching when told', () async {
    final player = _Player()..cid = 2;
    var shown = 0;
    final stop = watchFirstFrame(player, cid: () => 2, shown: () => shown++);
    player.dataStatus.value = DataStatus.loaded;
    await Future<void>.delayed(Duration.zero);
    stop();
    player
      ..playerStatus = PlayerStatus.playing
      ..playTo(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(shown, 0);
    expect(player._positionListeners, isEmpty);
  });
}
