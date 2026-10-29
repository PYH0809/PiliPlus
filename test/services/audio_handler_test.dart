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
    handler = VideoPlayerServiceHandler();
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
      'did', () {
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
    expect(actions(), contains(MediaAction.play));
  });

  test('the card knows whether it shows a page opened above another', () {
    handler
      ..onPageOpen('below')
      ..onPageOpen('listen')
      ..onPageOpen('above');
    addTearDown(() {
      for (final tag in ['below', 'listen', 'above']) {
        handler.onVideoDetailDispose(tag);
      }
    });

    handler.onVideoDetailChange(item(), 1, 'above');
    expect(handler.isShowingPageAbove('listen'), isTrue);

    // Such as the intro of the video below arriving late.
    handler.onVideoDetailChange(item(), 2, 'below');
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
