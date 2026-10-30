import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:audio_service/audio_service.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VideoPlayerServiceHandler handler;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-audio-handler-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    // The tests run on a desktop: the card behaves as on Android, where a
    // paused one goes after a while, unless a test says otherwise.
    handler = VideoPlayerServiceHandler()..pausedCardExpires = true;
  });

  tearDown(() => handler.clear());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  DetailItem item({List<BKArcPart> parts = const []}) => DetailItem(
    arc: BKArchive(
      title: '对肥胖和健康的新理解',
      cover: 'https://i0.hdslb.com/bfs/archive/cover.jpg',
      duration: Int64(1319),
    ),
    owner: Author(name: '云健身-仰望尾迹云'),
    parts: parts,
  );

  void play({bool canSkip = false}) => handler.onUpdateState(
    .playing,
    false,
    false,
    position: const Duration(seconds: 172),
    speed: 1,
    canSkip: canSkip,
  );

  List<MediaAction> actions() =>
      handler.playbackState.value.controls.map((e) => e.action).toList();

  test('the card shows the title, the uploader, the cover and the length', () {
    handler.onVideoDetailChange(item(), 1, 'audio');

    final mediaItem = handler.mediaItem.value!;
    expect(mediaItem.title, '对肥胖和健康的新理解');
    expect(mediaItem.artist, '云健身-仰望尾迹云');
    expect(mediaItem.artUri, isNotNull);
    expect(mediaItem.duration, const Duration(seconds: 1319));
  });

  test('a video in parts shows the part playing and its length', () {
    handler.onVideoDetailChange(
      item(
        parts: [
          BKArcPart(subId: Int64(1), title: 'P1 开场', duration: Int64(300)),
          BKArcPart(subId: Int64(2), title: 'P2 正文', duration: Int64(1019)),
        ],
      ),
      2,
      'audio',
    );

    final mediaItem = handler.mediaItem.value!;
    expect(mediaItem.title, 'P2 正文');
    expect(mediaItem.duration, const Duration(seconds: 1019));
  });

  test('with a playlist the card offers previous and next, and folds to '
      'them around play / pause', () {
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.updatePosition, const Duration(seconds: 172));
    expect(actions(), [
      MediaAction.rewind,
      MediaAction.skipToPrevious,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.fastForward,
    ]);
    expect(state.androidCompactActionIndices, [1, 2, 3]);
    expect(state.systemActions, contains(MediaAction.seek));
  });

  test('a video keeps rewind, play / pause and fast forward', () {
    handler.onVideoDetailChange(item(), 1, 'video');
    play(canSkip: true);
    play();

    expect(actions(), [
      MediaAction.rewind,
      MediaAction.pause,
      MediaAction.fastForward,
    ]);
    expect(handler.playbackState.value.androidCompactActionIndices, isNull);
  });

  test('back on a paused video page, the card is the video\'s again, without '
      'previous / next', () {
    handler
      ..onVideoDetailChange(item(), 1, 'video')
      ..onVideoDetailChange(
        item(
          parts: [
            BKArcPart(subId: Int64(1), title: 'P1 开场', duration: Int64(300)),
            BKArcPart(subId: Int64(2), title: 'P2 正文', duration: Int64(1019)),
          ],
        ),
        2,
        'audio',
      );
    play(canSkip: true);

    handler.onVideoDetailDispose('audio');

    final state = handler.playbackState.value;
    expect(handler.mediaItem.value!.id, '1video');
    expect(state.playing, isFalse);
    expect(actions(), [
      MediaAction.rewind,
      MediaAction.play,
      MediaAction.fastForward,
    ]);
    expect(state.androidCompactActionIndices, isNull);
  });

  test('a video taking the card from 听视频 drops previous / next before it '
      'plays', () {
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    handler.onVideoDetailChange(item(), 2, 'video');

    expect(handler.isShowing('video'), isTrue);
    expect(actions(), isNot(contains(MediaAction.skipToPrevious)));
    expect(actions(), isNot(contains(MediaAction.skipToNext)));
    expect(handler.playbackState.value.androidCompactActionIndices, isNull);
  });

  test('a new item keeps the progress where playback is now, not where it '
      'was last published', () {
    handler
      ..onVideoDetailChange(item(), 1, 'video')
      ..playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: true,
          updatePosition: const Duration(seconds: 172),
          updateTime: DateTime.now().subtract(const Duration(seconds: 10)),
        ),
      )
      // Such as the intro of the next video in a playlist arriving late.
      ..onVideoDetailChange(item(), 2, 'video');

    expect(
      handler.playbackState.value.updatePosition,
      greaterThanOrEqualTo(const Duration(seconds: 181)),
    );
  });

  test('a video taking the card from 听视频 does not play just because 听视频 '
      'did, nor from where 听视频 was', () {
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    // A video part, with no player of its own playing yet.
    handler.onVideoDetailChange(
      Part(cid: 2, part: 'MV', duration: 200),
      2,
      'video',
      artist: '茶理理理子',
    );

    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.updatePosition, Duration.zero);
    expect(actions(), contains(MediaAction.play));
  });

  test('the card knows whether it shows a page opened above another', () {
    handler
      ..onPageOpen('below')
      ..onPageOpen('listen')
      ..onPageOpen('above');
    addTearDown(() {
      for (final tag in ['below', 'listen', 'above']) {
        handler.onPageClose(tag);
      }
    });

    handler.onVideoDetailChange(item(), 1, 'above');
    expect(handler.isShowingPageAbove('listen'), isTrue);

    // Such as the intro of the video below arriving late.
    handler.onVideoDetailChange(item(), 2, 'below');
    expect(handler.isShowingPageAbove('listen'), isFalse);

    // A page closed, also by 返回主页, no longer counts.
    handler
      ..onVideoDetailChange(item(), 3, 'above')
      ..onPageClose('above');
    expect(handler.isShowingPageAbove('listen'), isFalse);
  });

  test('back on 听视频 after a video opened from it closes, the page can put '
      'its previous / next back', () async {
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);
    handler.onVideoDetailChange(item(), 2, 'video');
    play();
    expect(handler.isShowing('audio'), isFalse);

    // What 听视频 does when the card shows its item again.
    final subscription = handler.mediaItem.listen((_) {
      if (handler.isShowing('audio')) play(canSkip: true);
    });
    addTearDown(subscription.cancel);
    handler.onVideoDetailDispose('video');
    await pumpEventQueue();

    expect(handler.isShowing('audio'), isTrue);
    expect(actions(), contains(MediaAction.skipToPrevious));
    expect(actions(), contains(MediaAction.skipToNext));
  });

  test('a paused card keeps its foreground service, so that play on it does '
      'not have to start the service again from the background', () {
    expect(audioServiceConfig.androidStopForegroundOnPause, isFalse);
  });

  test('a paused card gives up its foreground service after a while, and '
      'playing again brings it back', () async {
    handler.pausedCardLifetime = const Duration(milliseconds: 30);
    addTearDown(() => handler.pausedCardLifetime = const Duration(minutes: 10));
    handler.onVideoDetailChange(item(), 1, 'video');

    play();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );

    play();
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('swiped away from recents, a paused card goes and a playing one '
      'stays', () async {
    handler.onVideoDetailChange(item(), 1, 'video');
    play();

    await handler.onTaskRemoved();
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
    );
    await handler.onTaskRemoved();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );

    // The page still has its item: playing again brings the card back.
    play();
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('a pause that reaches the card just after the app is swiped away '
      'takes the card away too', () async {
    handler.onVideoDetailChange(item(), 1, 'video');
    play();

    await handler.onTaskRemoved();
    // The players tell the card of a pause half a second late, such as one
    // from opening recents just before the swipe.
    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('a pause from the card just after the swipe is a new one, and keeps '
      'the card', () async {
    handler.onVideoDetailChange(item(), 1, 'video');
    play();

    await handler.onTaskRemoved();
    await handler.pause();
    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('unplugging the headphones just after the swipe is a new pause, and '
      'keeps the card', () async {
    handler.onVideoDetailChange(item(), 1, 'video');
    play();

    await handler.onTaskRemoved();
    handler
      ..onBecomingNoisy()
      ..onUpdateState(
        .paused,
        false,
        false,
        position: const Duration(seconds: 180),
        speed: 1,
      );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('a paused card waits out a call longer than its time, swiped away or '
      'not, so that the player can play on after it', () async {
    var waits = false;
    handler
      ..pausedCardLifetime = const Duration(milliseconds: 30)
      ..waitsToPlayOn = () => waits;
    addTearDown(() {
      handler
        ..pausedCardLifetime = const Duration(minutes: 10)
        ..waitsToPlayOn = null;
    });
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    // The call pauses the player, which waits to play on after it.
    waits = true;
    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
      canSkip: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await handler.onTaskRemoved();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );

    // Over, and nothing plays on: the card goes in its own time.
    waits = false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('previous / next on a paused card start its clock again, as the next '
      'one takes a moment to load and play', () async {
    handler.pausedCardLifetime = const Duration(milliseconds: 100);
    addTearDown(() => handler.pausedCardLifetime = const Duration(minutes: 10));
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
      canSkip: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await handler.skipToNext();
    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('a card that shows paused stays through a call when its player waits '
      'to play on after it, such as 听视频 waiting for the next one', () async {
    addTearDown(() => handler.waitsToPlayOn = null);
    handler
      ..onVideoDetailChange(item(), 1, 'audio')
      ..onUpdateState(
        .completed,
        false,
        false,
        position: const Duration(seconds: 1319),
        speed: 1,
        canSkip: true,
      )
      // A call begins while the next one loads.
      ..waitsToPlayOn = (() => true);
    await handler.onTaskRemoved();

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.completed,
    );
  });

  test('off Android a paused card stays, as it holds no foreground '
      'service there', () async {
    handler
      ..pausedCardExpires = false
      ..pausedCardLifetime = const Duration(milliseconds: 30);
    addTearDown(() {
      handler
        ..pausedCardExpires = true
        ..pausedCardLifetime = const Duration(minutes: 10);
    });
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
      canSkip: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
  });

  test('as a call ends, the paused card\'s clock starts again, so that the '
      'card does not go while the player plays on', () async {
    var waits = true;
    handler
      ..pausedCardLifetime = const Duration(milliseconds: 100)
      ..waitsToPlayOn = () => waits;
    addTearDown(() {
      handler
        ..pausedCardLifetime = const Duration(minutes: 10)
        ..waitsToPlayOn = null;
    });
    handler.onVideoDetailChange(item(), 1, 'video');
    play();

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    // The call ends just before the card's time. The player plays on, but
    // only tells the card a little later.
    handler.onInterruptionEnd();
    waits = false;
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );

    play();
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('the paused card\'s clock runs on through updates while it stays '
      'paused, such as a seek', () async {
    handler.pausedCardLifetime = const Duration(milliseconds: 100);
    addTearDown(() => handler.pausedCardLifetime = const Duration(minutes: 10));
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
      canSkip: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 300),
      speed: 1,
      canSkip: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('play on a paused card starts its clock again, so the card neither '
      'goes while playing starts nor stays if it never does', () async {
    handler.pausedCardLifetime = const Duration(milliseconds: 100);
    addTearDown(() => handler.pausedCardLifetime = const Duration(minutes: 10));
    handler.onVideoDetailChange(item(), 1, 'video');
    play();

    handler.onUpdateState(
      .paused,
      false,
      false,
      position: const Duration(seconds: 180),
      speed: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    // No player here takes it, as when audio focus is refused.
    await handler.play();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('leaving the page takes the card away', () {
    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    handler
      ..onVideoDetailDispose('audio')
      ..clearIfNeeded();

    expect(handler.mediaItem.value, isNull);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('with 后台音频服务 off the card stays away', () {
    handler.enableBackgroundPlay = false;
    addTearDown(() => handler.enableBackgroundPlay = true);

    handler.onVideoDetailChange(item(), 1, 'audio');
    play(canSkip: true);

    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.playing, isFalse);
  });
}
