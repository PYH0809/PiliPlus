import 'dart:async' show Timer;
import 'dart:io' show File, Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart' show DetailItem;
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/live/live_room_info_h5/data.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/local/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart'
    show audioSessionHandler;
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/src/extension_instance.dart';
import 'package:jni/jni.dart' show JStringExtension;
import 'package:path/path.dart' as path;

Future<VideoPlayerServiceHandler> initAudioService() {
  if (Platform.isLinux) {
    AudioServiceMpris.init(
      dBusName: 'com.example.piliplus.audio',
      identity: 'Audio Service ${Constants.appName}',
      canGoNext: true,
      canGoPrevious: true,
      canPlay: true,
      canPause: true,
      canControl: true,
    );
  }
  return AudioService.init(
    builder: VideoPlayerServiceHandler.new,
    config: audioServiceConfig,
  );
}

const audioServiceConfig = AudioServiceConfig(
  androidNotificationChannelId: 'com.example.piliplus.audio',
  androidNotificationChannelName: 'Audio Service ${Constants.appName}',
  // The foreground service stays while paused. Without it, Android stops the
  // service about a minute after the app pauses in the background, and play
  // on the lock screen or in the control center then has to start it again
  // from the background, which Android 12 and later refuse. A paused card
  // gives it up after a while (pausedCardLifetime) or when the app is swiped
  // away from recents.
  androidStopForegroundOnPause: false,
  fastForwardInterval: Duration(seconds: 10),
  rewindInterval: Duration(seconds: 10),
  androidNotificationChannelDescription: 'Media notification channel',
  androidNotificationIcon: 'drawable/ic_notification_icon',
);

typedef _StatusConfig = (
  PlayerStatus status,
  bool isBuffering,
  bool isLive,
  double speed,
  bool canSkip,
);

class VideoPlayerServiceHandler extends BaseAudioHandler with SeekHandler {
  VideoPlayerServiceHandler() {
    playbackState.listen(_onPlaybackState);
    if (Platform.isAndroid) {
      final jStr = AndroidHelper.manufacturer();
      if (jStr != null &&
          jStr.toDartString(releaseOriginal: true).toLowerCase() == 'vivo') {
        androidPlaybackInfo.add(
          RemoteAndroidPlaybackInfo(
            volumeControlType: .fixed,
            maxVolume: 100,
            volume: 50,
          ),
        );
      }
    }
  }

  static final List<MediaItem> _item = [];
  bool enableBackgroundPlay = Pref.enableBackgroundPlay;

  Future<void>? Function()? onPlay;
  Future<void>? Function()? onPause;
  Future<void>? Function(Duration position)? onSeek;
  void Function()? onSkipToNext;
  void Function()? onSkipToPrevious;

  @override
  Future<void> play() {
    _onControl();
    return onPlay?.call() ??
        PlPlayerController.playIfExists() ??
        Future.syncValue(null);
  }

  @override
  Future<void> pause() {
    _onControl();
    return onPause?.call() ??
        PlPlayerController.pauseIfExists() ??
        Future.syncValue(null);
  }

  CommonIntroController? _findIntroController() {
    final playOwner = PlPlayerController.playOwner;
    if (playOwner != null) {
      final tag = playOwner.tag;
      try {
        return switch (playOwner.type) {
          UgcIntroController _ => Get.find<UgcIntroController>(tag: tag),
          PgcIntroController _ => Get.find<PgcIntroController>(tag: tag),
          LocalIntroController _ => Get.find<LocalIntroController>(tag: tag),
          _ => throw UnimplementedError(playOwner.type.toString()),
        };
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }
    return null;
  }

  @override
  Future<void> skipToNext() {
    _onControl();
    final func = onSkipToNext ?? _findIntroController()?.nextPlay;
    return func == null ? Future.syncValue(null) : Future.sync(func);
  }

  @override
  Future<void> skipToPrevious() {
    _onControl();
    final func = onSkipToPrevious ?? _findIntroController()?.prevPlay;
    return func == null ? Future.syncValue(null) : Future.sync(func);
  }

  @override
  Future<void> seek(Duration position) {
    return onSeek?.call(position) ??
        PlPlayerController.seekToIfExists(position, isSeek: false) ??
        Future.syncValue(null);
  }

  void setMediaItem(MediaItem newMediaItem) {
    if (!enableBackgroundPlay) return;
    // if (kDebugMode) {
    //   debugPrint("此时调用栈为：");
    //   debugPrint(newMediaItem);
    //   debugPrint(newMediaItem.title);
    //   debugPrint(StackTrace.current.toString());
    // }
    if (!mediaItem.isClosed) mediaItem.add(newMediaItem);
  }

  Duration? _lastPos;
  _StatusConfig? _lastConfig;
  void onUpdateState(
    PlayerStatus status,
    bool isBuffering,
    bool isLive, {
    required Duration position,
    required double speed,
    bool canSkip = false,
    String? debugLabel,
  }) {
    if (!enableBackgroundPlay || _item.isEmpty) {
      return;
    }

    if (onPlay != null && debugLabel == 'onVideoPaused') return;

    if (status == .playing) {
      // Only a player playing settles it, not the card's state sent again,
      // such as with the next one's details while the end is on its way.
      goesOn = false;
      _cardGone = false;
    } else if (_cardGone) {
      // Gone after its time or a swipe, the card comes back only as a player
      // plays, or with a new item, not with a paused player's later updates.
      return;
    }

    final newConfig = (status, isBuffering, isLive, speed, canSkip);
    if (_lastConfig == newConfig) {
      if (_lastPos != null) {
        final pos = position.inSeconds;
        final lastPos = _lastPos!.inSeconds;
        _lastPos = position;
        if (pos == lastPos && pos != 0) return;
      }
    }
    _lastConfig = newConfig;

    final AudioProcessingState processingState;
    final bool playing;
    switch (status) {
      case .completed:
        playing = false;
        processingState = .completed;
      case .playing:
        playing = true;
        processingState = isBuffering ? .buffering : .ready;
      case .paused:
        playing = isBuffering;
        processingState = isBuffering ? .buffering : .ready;
    }
    _pausedWhileBuffering = status == .paused && isBuffering;
    _updateState(
      processingState,
      playing,
      isLive,
      position: position,
      speed: speed,
      canSkip: canSkip,
    );
  }

  /// [canSkip] adds previous / next, for a page with its own playlist.
  void _updateState(
    AudioProcessingState state,
    bool playing,
    bool isLive, {
    required Duration position,
    required double speed,
    bool canSkip = false,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: state,
        updatePosition: position,
        speed: speed,
        controls: [
          if (!isLive)
            const MediaControl(
              androidIcon: 'drawable/ic_player_rewind_10s',
              label: 'Rewind',
              action: .rewind,
            ),
          if (canSkip)
            const MediaControl(
              androidIcon: 'drawable/ic_player_skip_previous',
              label: 'Previous',
              action: .skipToPrevious,
            ),
          if (playing)
            const MediaControl(
              androidIcon: 'drawable/ic_player_pause',
              label: 'Pause',
              action: .pause,
            )
          else
            const MediaControl(
              androidIcon: 'drawable/ic_player_play',
              label: 'Play',
              action: .play,
            ),
          if (canSkip)
            const MediaControl(
              androidIcon: 'drawable/ic_player_skip_next',
              label: 'Next',
              action: .skipToNext,
            ),
          if (!isLive)
            const MediaControl(
              androidIcon: 'drawable/ic_player_fast_forward_10s',
              label: 'Fast Forward',
              action: .fastForward,
            ),
        ],
        // Android 12 and lower fold the notification to three buttons:
        // previous, play / pause and next, as music apps do.
        androidCompactActionIndices: canSkip && !isLive
            ? const [1, 2, 3]
            : null,
        playing: playing,
        systemActions: const {.seek},
      ),
    );
    if (Platform.isAndroid &&
        (AndroidHelper.isPipMode ||
            PlPlayerController.instance?.isAutoEnterPip == true)) {
      AndroidHelper.updatePipActions(
        PlatformDispatcher.instance.engineId!,
        isLive,
        playing,
      );
    }
  }

  void onVideoDetailChange(
    dynamic data,
    int cid,
    String herotag, {
    String? artist,
    String? cover,
  }) {
    if (!enableBackgroundPlay) return;
    // if (kDebugMode) {
    //   debugPrint('当前调用栈为：');
    //   debugPrint(StackTrace.current);
    // }
    if (data == null) return;
    _cardGone = false;

    Uri getUri(String? cover) => Uri.parse(ImageUtils.safeThumbnailUrl(cover));

    late final id = '$cid$herotag';
    final MediaItem mediaItem;
    switch (data) {
      case VideoDetailData(:final pages):
        if (pages != null && pages.length > 1) {
          final current = pages.firstWhereOrNull((e) => e.cid == cid);
          mediaItem = MediaItem(
            id: id,
            title: current?.part ?? '',
            artist: data.owner?.name,
            duration: Duration(seconds: current?.duration ?? 0),
            artUri: getUri(data.pic),
          );
        } else {
          mediaItem = MediaItem(
            id: id,
            title: data.title ?? '',
            artist: data.owner?.name,
            duration: Duration(seconds: data.duration ?? 0),
            artUri: getUri(data.pic),
          );
        }
      case EpisodeItem():
        mediaItem = MediaItem(
          id: id,
          title: data.showTitle ?? data.longTitle ?? data.title ?? '',
          artist: artist,
          duration: data.from == 'pugv'
              ? Duration(seconds: data.duration ?? 0)
              : Duration(milliseconds: data.duration ?? 0),
          artUri: getUri(data.cover),
        );
      case RoomInfoH5Data():
        mediaItem = MediaItem(
          id: id,
          title: data.roomInfo?.title ?? '',
          artist: data.anchorInfo?.baseInfo?.uname,
          artUri: getUri(data.roomInfo?.cover),
          isLive: true,
        );
      case Part():
        mediaItem = MediaItem(
          id: id,
          title: data.part ?? '',
          artist: artist,
          duration: Duration(seconds: data.duration ?? 0),
          artUri: getUri(cover),
        );
      case DetailItem(:final arc, :final parts):
        final part = parts.length > 1
            ? parts.firstWhereOrNull((e) => e.subId.toInt() == cid)
            : null;
        mediaItem = MediaItem(
          id: id,
          title: part?.title ?? arc.title,
          artist: data.owner.name,
          duration: Duration(seconds: (part?.duration ?? arc.duration).toInt()),
          artUri: getUri(arc.cover),
        );
      case BiliDownloadEntryInfo():
        final coverFile = File(
          path.join(data.entryDirPath, PathUtils.coverName),
        );
        final uri = coverFile.existsSync()
            ? coverFile.absolute.uri
            : getUri(data.cover);
        mediaItem = MediaItem(
          id: id,
          title: data.showTitle,
          artist: data.ownerName,
          duration: Duration(milliseconds: data.totalTimeMilli),
          artUri: uri,
        );
      default:
        return;
    }
    // A page taking the card from another neither plays because that one did
    // nor starts from where that one was: a video takes its player's status
    // and position once the shared player holds its video, and where it has
    // got to itself before; 听视频 republishes its own state on hearing its
    // item.
    bool? playing;
    Duration? position;
    if (!isShowing(herotag)) {
      final holds = switch (data) {
        DetailItem() => false,
        // A room has one stream, and the player keeps no cid for it.
        RoomInfoH5Data() => PlPlayerController.playOwner?.tag == herotag,
        _ => _playerHolds(herotag, cid),
      };
      playing =
          holds &&
          (PlPlayerController.getPlayerStatusIfExists()?.isPlaying ?? false);
      position = _positionOf(herotag, holds);
    }
    _item.add(mediaItem);
    _resetControls(mediaItem, playing: playing, position: position);
    setMediaItem(mediaItem);
  }

  /// Rebuilds the card's buttons for [item], which takes the card from a page
  /// that may have had previous / next, or been live. They go before the item,
  /// so that a page with a playlist, hearing its item, puts its own back.
  void _resetControls(
    MediaItem item, {
    AudioProcessingState? state,
    bool? playing,
    Duration? position,
  }) {
    final current = playbackState.value;
    _updateState(
      state ?? current.processingState,
      playing ?? current.playing,
      item.isLive ?? false,
      // By default where playback is now: the last update's position, run on
      // since.
      position: position ?? current.position,
      speed: current.speed,
    );
  }

  void onVideoDetailDispose(String herotag) {
    if (!enableBackgroundPlay) return;

    if (_item.isNotEmpty) {
      _item.removeWhere((item) => item.id.endsWith(herotag));
    }
    if (_item.isNotEmpty) {
      final item = _item.last;
      // The page underneath shows where it is itself, not where the shared
      // player was for the page that left; 听视频 republishes its own state on
      // hearing its item, which a card gone with the page above must take.
      _cardGone = false;
      final tag = _pages.lastWhereOrNull(item.id.endsWith);
      final cid = tag == null
          ? null
          : int.tryParse(item.id.substring(0, item.id.length - tag.length));
      _resetControls(
        item,
        state: .ready,
        playing: false,
        position: _positionOf(
          tag,
          tag != null && cid != null && _playerHolds(tag, cid),
        ),
      );
      setMediaItem(item);
    }
  }

  /// Whether the card shows the page tagged [herotag].
  bool isShowing(String herotag) =>
      mediaItem.value?.id.endsWith(herotag) ?? false;

  /// The hero tags of the open pages that can put an item on the card, in the
  /// order they opened.
  final List<String> _pages = [];

  /// Whether the shared player holds the video [cid] of the page tagged
  /// [herotag], rather than one of the page it served before.
  static bool _playerHolds(String herotag, int cid) =>
      PlPlayerController.playOwner?.tag == herotag &&
      PlPlayerController.instance?.cid == cid;

  /// Where the video page tagged [herotag] has got to: the shared player's
  /// position when it [holds] the page's video, else what the page kept
  /// itself; zero for other pages.
  static Duration _positionOf(String? herotag, bool holds) {
    if (holds) {
      return Duration(
        milliseconds: PlPlayerController.instance!.positionInMilliseconds,
      );
    }
    if (herotag == null ||
        !Get.isRegistered<VideoDetailController>(tag: herotag)) {
      return Duration.zero;
    }
    return Get.find<VideoDetailController>(tag: herotag).playedTime ??
        Duration.zero;
  }

  /// Notes a page that can put an item on the card as it opens.
  void onPageOpen(String herotag) => _pages.add(herotag);

  /// Forgets a page noted with [onPageOpen] as it closes.
  void onPageClose(String herotag) => _pages.remove(herotag);

  /// Whether the card shows a page opened after the one tagged [herotag], and
  /// so above it.
  bool isShowingPageAbove(String herotag) {
    final id = mediaItem.value?.id;
    final index = _pages.indexOf(herotag);
    if (id == null || index == -1) return false;
    return _pages.skip(index + 1).any(id.endsWith);
  }

  void clearIfNeeded() {
    if (!enableBackgroundPlay) return;
    if (_item.isEmpty) clear();
  }

  /// How long a paused card keeps the foreground service, and the wake lock
  /// audio_service holds with it, before it goes. The pages keep their items,
  /// so playing again brings it back.
  @visibleForTesting
  Duration pausedCardLifetime = const Duration(minutes: 10);
  Timer? _pausedCardTimer;

  /// Whether a paused card goes after a while: only on Android, where it
  /// holds the foreground service. Elsewhere it stays, as it always has.
  @visibleForTesting
  bool pausedCardExpires = Platform.isAndroid;

  /// The players tell the card of a pause half a second late, so a pause it
  /// hears of this soon after the app is swiped away from recents came before
  /// the swipe, or from it.
  static const _latePause = Duration(seconds: 1);
  DateTime? _taskRemovedAt;

  /// Whether the player is paused while it buffers, which the card shows as
  /// playing.
  bool _pausedWhileBuffering = false;

  bool _isPaused(PlaybackState state) =>
      state.processingState != .idle &&
      (!state.playing ||
          (_pausedWhileBuffering && state.processingState == .buffering));

  /// Takes the card's service out of the foreground, which takes its
  /// notification with it. The service stays there while paused, and as the
  /// card goes idle audio_service only cancels the notification, which
  /// Android refuses for a foreground service, and stops the service, which
  /// the app's own media browser keeps bound: the card stayed. Only Android
  /// has the foreground service.
  @visibleForTesting
  void Function()? leaveForeground = Platform.isAndroid
      ? AndroidHelper.stopMediaForeground
      : null;

  AudioProcessingState _processingState = .idle;

  /// Starts the paused card's clock as the card stops playing. Updates while
  /// it stays paused, such as a seek, leave the clock running. A card going
  /// idle leaves the foreground ([leaveForeground]).
  void _onPlaybackState(PlaybackState state) {
    final wasIdle = _processingState == .idle;
    _processingState = state.processingState;
    if (!wasIdle && state.processingState == .idle) leaveForeground?.call();
    if (!_isPaused(state)) {
      _pausedCardTimer?.cancel();
      _pausedCardTimer = null;
      _swipeTimer?.cancel();
    } else if (_pausedCardTimer == null && pausedCardExpires) {
      _pausedCardTimer = Timer(pausedCardLifetime, _onPausedCardTimeout);
      final taskRemovedAt = _taskRemovedAt;
      if (taskRemovedAt != null &&
          DateTime.now().difference(taskRemovedAt) < _latePause) {
        _endSwipedAwayCard();
      }
    }
  }

  /// Whether 听视频 waits out a call or the like, to play on by itself after
  /// it. A video tells through the audio session.
  bool Function()? waitsToPlayOn;

  /// Whether 听视频 plays or is about to, such as while the next one loads.
  bool Function()? aboutToPlay;

  /// Whether a player says it goes on by itself: the video page, having
  /// played one through, with the next one or the same one again (also once
  /// a related one it asks for arrives), or a player whose wait for a call is
  /// over. A player playing or the card going clears it.
  bool goesOn = false;

  /// Whether a player waits out a call or the like, to play on by itself
  /// after it, from the background. A paused card stays meanwhile: had it
  /// gone, playing on would have to start the foreground service again, which
  /// Android 12 and later refuse.
  bool get _waitsToPlayOn =>
      (waitsToPlayOn?.call() ?? false) ||
      (audioSessionHandler?.videoWaitsToPlayOn ?? false);

  /// A player that waited out a call or the like no longer does: it plays on
  /// as the call ends, which takes a moment, or it never will, such as with
  /// focus lost for good. Either way the clock starts again, so that the card
  /// neither goes meanwhile nor before its full time, and a swipe meanwhile
  /// gives it [goingOnTime] to play. A pause still on its way to the card
  /// came from the wait, not from before a swipe.
  void onWaitOver() {
    _taskRemovedAt = null;
    goesOn = true;
    _restartPausedCardClock();
    if (_swipeTimer?.isActive ?? false) _waitForSwipedCardToPlay();
  }

  void _onPausedCardTimeout() {
    if (_waitsToPlayOn) {
      _pausedCardTimer = Timer(pausedCardLifetime, _onPausedCardTimeout);
    } else {
      _endPausedCard();
    }
  }

  /// Play, pause, previous or next on the card, or from a headset. After the
  /// swipe, a pause from here is a new one, which keeps the card.
  void _onControl() {
    _taskRemovedAt = null;
    _swipeTimer?.cancel();
    _restartPausedCardClock();
  }

  /// Starts a paused card's clock again as it may play on, which takes a
  /// moment, such as for audio focus: the card does not go meanwhile, nor
  /// stay for good if it never plays.
  void _restartPausedCardClock() {
    if (_pausedCardTimer case final timer?) {
      timer.cancel();
      _pausedCardTimer = Timer(pausedCardLifetime, _onPausedCardTimeout);
    }
  }

  /// Unplugged headphones pause the players without the card. After the
  /// swipe, that is a new pause too, which keeps the card.
  void onBecomingNoisy() {
    _taskRemovedAt = null;
    _swipeTimer?.cancel();
  }

  /// Lets a paused card go, and the foreground service with it. It goes as
  /// not playing, though one paused while it buffers shows as playing: the
  /// service takes the foreground again, and its media session up, only as
  /// the card goes from not playing to playing.
  void _endPausedCard() {
    final state = playbackState.value;
    if (_isPaused(state)) {
      goesOn = false;
      _cardGone = true;
      playbackState.add(
        state.copyWith(processingState: .idle, playing: false),
      );
    }
  }

  /// Whether the paused card went after its time or a swipe. Its item coming
  /// back, or another's, brings it back.
  bool _cardGone = false;

  /// How long after a swipe a paused card whose player says it goes on by
  /// itself stays for it to play: past it, the next one is not coming, such
  /// as when its details or its address could not be had.
  @visibleForTesting
  Duration goingOnTime = const Duration(seconds: 30);
  Timer? _swipeTimer;

  /// Lets a paused card go after a swipe: at once, or, when its player says
  /// it goes on by itself ([goesOn], [aboutToPlay]), if it has not played
  /// within [goingOnTime]. One whose player waits out a call stays, its clock
  /// bounding it.
  void _endSwipedAwayCard() {
    if (_waitsToPlayOn) return;
    if (goesOn || (aboutToPlay?.call() ?? false)) {
      _waitForSwipedCardToPlay();
    } else {
      _endPausedCard();
    }
  }

  /// Gives a swiped card [goingOnTime] from now to play, or it goes. Its
  /// player has just said it goes on, so its clock starts again too, and
  /// cannot end it sooner.
  void _waitForSwipedCardToPlay() {
    _restartPausedCardClock();
    _swipeTimer?.cancel();
    _swipeTimer = Timer(goingOnTime, () {
      if (!_waitsToPlayOn) _endPausedCard();
    });
  }

  /// Swiped away from recents, a paused card goes ([_endSwipedAwayCard]); a
  /// playing one stays, playing on in the background.
  @override
  Future<void> onTaskRemoved() async {
    _taskRemovedAt = DateTime.now();
    if (_isPaused(playbackState.value)) _endSwipedAwayCard();
  }

  void clear() {
    if (!enableBackgroundPlay) return;
    mediaItem.add(null);
    _item.clear();
    _lastPos = null;
    _lastConfig = null;
    _taskRemovedAt = null;
    _pausedWhileBuffering = false;
    goesOn = false;
    _cardGone = false;
    _swipeTimer?.cancel();
    /**
     * if (playbackState.processingState == AudioProcessingState.idle &&
            previousState?.processingState != AudioProcessingState.idle) {
          await AudioService._stop();
        }
     */
    if (playbackState.value.processingState == .idle) {
      playbackState.add(PlaybackState(processingState: .completed));
    }
    playbackState.add(PlaybackState(processingState: .idle));
  }
}
