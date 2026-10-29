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
import 'package:PiliPlus/pages/video/introduction/local/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
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
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.piliplus.audio',
      androidNotificationChannelName: 'Audio Service ${Constants.appName}',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
      androidNotificationChannelDescription: 'Media notification channel',
      androidNotificationIcon: 'drawable/ic_notification_icon',
    ),
  );
}

typedef _StatusConfig = (
  PlayerStatus status,
  bool isBuffering,
  bool isLive,
  double speed,
  bool canSkip,
);

class VideoPlayerServiceHandler extends BaseAudioHandler with SeekHandler {
  VideoPlayerServiceHandler() {
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
    return onPlay?.call() ??
        PlPlayerController.playIfExists() ??
        Future.syncValue(null);
  }

  @override
  Future<void> pause() {
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
    final func = onSkipToNext ?? _findIntroController()?.nextPlay;
    return func == null ? Future.syncValue(null) : Future.sync(func);
  }

  @override
  Future<void> skipToPrevious() {
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
    // and position, and 听视频 republishes its own state on hearing its item.
    bool? playing;
    Duration? position;
    if (!isShowing(herotag)) {
      final player = data is DetailItem ? null : PlPlayerController.instance;
      playing = player?.playerStatus.isPlaying ?? false;
      position = Duration(
        milliseconds: playing ? player!.positionInMilliseconds : 0,
      );
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
      // The page underneath shows where its player is; 听视频 republishes its
      // own state on hearing its item.
      _resetControls(
        item,
        state: .ready,
        playing: false,
        position: Duration(
          milliseconds:
              PlPlayerController.instance?.positionInMilliseconds ?? 0,
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

  void clear() {
    if (!enableBackgroundPlay) return;
    mediaItem.add(null);
    _item.clear();
    _lastPos = null;
    _lastConfig = null;
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
