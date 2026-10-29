import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/audio.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart'
    show
        DetailItem,
        PlayURLResp,
        PlaylistSource,
        PlayInfo,
        ListOrder,
        DashItem,
        ResponseUrl;
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/audio_normalization.dart';
import 'package:PiliPlus/models/video/play/url.dart' as http_model show Volume;
import 'package:PiliPlus/pages/audio/subtitle/subtitle_mixin.dart';
import 'package:PiliPlus/pages/sponsor_block/block_mixin.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:audio_session/audio_session.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

class AudioController extends GetxController
    with
        GetTickerProviderStateMixin,
        BlockConfigMixin,
        BlockMixin,
        AudioNormalizationMixin,
        AudioSubtitleMixin {
  late Int64 id;
  late Int64 oid;
  late List<Int64> subId;
  late int itemType;
  Int64? extraId;
  late final PlaylistSource from;
  @override
  late final bool isUgc = itemType == 1;

  /// The video and part playing, once their media opened: the next one's
  /// address may still fail, and this one plays on.
  @override
  (int, int)? subtitleTarget;

  final audioItem = Rxn<DetailItem>();

  bool _hasInit = false;
  @override
  Player? player;
  late int cacheAudioQa;

  late bool isDragging = false;
  final RxInt position = RxInt(0);
  final RxInt duration = RxInt(0);

  late final AnimationController animController;

  List<StreamSubscription>? _subscriptions;
  StreamSubscription? _mediaItemSubscription;

  /// Whether a page opened from here, such as 看MV's video, covers this one.
  bool isCovered = false;

  /// Back on top: an item held back while covered goes to the card, which
  /// also republishes the state.
  void onUncovered() {
    isCovered = false;
    _bindMediaControls();
    _reclaimMediaCard();
  }

  /// Hands this page's item to the card when the card shows another one, or
  /// one from before the part or item changed.
  void _reclaimMediaCard() {
    if (_isCardStale ||
        videoPlayerServiceHandler?.isShowing(hashCode.toString()) == false) {
      if (audioItem.value case final item?) _updateMediaItem(item);
    }
  }

  /// Whether the card holds an item from before the part or item changed.
  bool _isCardStale = false;

  int? index;
  List<DetailItem>? playlist;

  late double speed = 1.0;

  void setSpeed(double value) {
    if (player case final player?) {
      speed = value;
      player.setRate(value);
      updateSubtitleRate(value);
      _updatePlaybackState();
    }
  }

  late final Rx<PlayRepeat> playMode = Pref.audioPlayMode.obs;

  Duration? _start;
  VideoDetailController? _videoDetailController;

  String? _prev;
  String? _next;
  bool get reachStart => _prev == null;

  ListOrder order = ListOrder.ORDER_NORMAL;

  double? _lastVolume;
  late final RxDouble desktopVolume = RxDouble(Pref.desktopVolume);

  bool _playInterrupted = false;
  double? _volumeBeforeDuck;
  // 页面要不要在放：开播、点选一首时为 true；暂停、被打断、播完不再接着放时为 false。
  // 等播放器、等下一首地址的自动播放，开播前都再看一眼它
  bool _wantPlay = true;
  // 等焦点的开播请求的编号：暂停、切曲、被打断都会作废还没等到焦点的请求
  int _playRequest = 0;
  // 地址请求的编号：连着切了几次时只认最新一次的结果
  int _urlRequest = 0;
  int _urlReturned = 0;
  // 点了别的一首、地址还没回来
  bool get _switchingTrack => _urlReturned != _urlRequest;

  Timer? _statusTimer;

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer(
      const Duration(milliseconds: 500),
      _updatePlaybackState,
    );
  }

  void _stopStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void toggleVolume() {
    if (_lastVolume == null) {
      _lastVolume = desktopVolume.value;
      setVolume(0, clearLastVolme: false);
    } else {
      setVolume(_lastVolume!);
    }
  }

  void setVolume(double volume, {bool clearLastVolme = true}) {
    if (clearLastVolme) {
      _lastVolume = null;
    }
    desktopVolume.value = volume;
    setPlayerVolume(volume * 100);
  }

  /// duck 期间用户调过音量的话，以用户的为准，duck 结束时不再恢复
  void setPlayerVolume(double volume) {
    _volumeBeforeDuck = null;
    player?.setVolume(volume);
  }

  void syncVolume([_]) {
    final volume = desktopVolume.value;
    PlPlayerController.instance
      ?..volume.value = volume
      ..videoPlayerController?.setVolume(volume * 100);
    GStorage.setting.put(SettingBoxKey.desktopVolume, volume.toPrecision(3));
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    oid = Int64(args['oid']);
    final id = args['id'];
    this.id = id != null ? Int64(id) : oid;
    subId = (args['subId'] as List<int>?)?.map(Int64.new).toList() ?? [oid];
    itemType = args['itemType'];
    from = args['from'];
    _start = args['start'];
    final int? extraId = args['extraId'];
    if (extraId != null) {
      this.extraId = Int64(extraId);
    }
    if (args['heroTag'] case String heroTag) {
      try {
        _videoDetailController = Get.find<VideoDetailController>(tag: heroTag);
      } catch (_) {}
    }

    _queryPlayList(isInit: true);

    final String? audioUrl = args['audioUrl'];
    final hasAudioUrl = audioUrl != null;
    if (hasAudioUrl) {
      _querySponsorBlock();
      _onOpenMedia(
        audioUrl,
        ua: BrowserUa.pc,
        referer: HttpString.baseUrl,
        volume: _videoDetailController?.volume,
      );
    }
    ConnectivityUtils.isWiFi.then((isWiFi) {
      cacheAudioQa = isWiFi ? Pref.defaultAudioQa : Pref.defaultAudioQaCellular;
      if (!hasAudioUrl) {
        _queryPlayUrl();
      }
    });
    videoPlayerServiceHandler?.onPageOpen(hashCode.toString());
    _bindMediaControls();
    // When the card shows this page again, such as after a page opened from
    // here closes, it gets this page's controls, state and previous / next
    // back.
    _mediaItemSubscription = videoPlayerServiceHandler?.mediaItem.listen((_) {
      final handler = videoPlayerServiceHandler!;
      final tag = hashCode.toString();
      if (!handler.isShowing(tag)) {
        if (handler.isShowingPageAbove(tag)) {
          // A page opened from here took the card, and its buttons with it.
          // This page stops playing as well, as it does for 看MV, so that no
          // sound goes on that the card cannot pause, and lets go of its audio
          // focus and of a play still waiting for it.
          _unbindMediaControls();
          onPause();
        } else if (!isCovered) {
          // On top, the card is this page's, also when a page below, such as
          // the video this was opened from, hands its item over late.
          _reclaimMediaCard();
        }
        // An item from a page below while a page such as 举报 covers this one
        // waits: this page takes the card back once it is on top again.
        return;
      }
      // Another 听视频 opened from here unbound them as it closed.
      _bindMediaControls();
      if (_isCardStale) {
        if (audioItem.value case final item?) {
          // Its item goes up to date first, and that republishes the state.
          _updateMediaItem(item);
          return;
        }
      }
      onPlaylistChanged();
    });

    animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    if (shutdownTimerService.isActive) {
      shutdownTimerService
        ..onPause = onPause
        ..isPlaying = isPlayingOrPending;
    }
  }

  /// Lets the card's buttons drive this page.
  void _bindMediaControls() {
    videoPlayerServiceHandler
      ?..onPlay = onPlay
      ..onPause = onPause
      ..onSeek = onSeek
      ..onSkipToNext = playNext
      ..onSkipToPrevious = playPrev;
  }

  /// Lets go of the card's buttons, if they are still this page's.
  void _unbindMediaControls() {
    final handler = videoPlayerServiceHandler;
    if (handler == null || handler.onPlay != onPlay) return;
    handler
      ..onPlay = null
      ..onPause = null
      ..onSeek = null
      ..onSkipToNext = null
      ..onSkipToPrevious = null;
  }

  @override
  bool isPlaying() {
    return player?.state.playing ?? false;
  }

  /// 在放，或者等着接着放（被打断、在等下一首）；定时关闭到点时要停掉它
  bool isPlayingOrPending() => isPlaying() || _wantPlay || _playInterrupted;

  @override
  Future<void>? onPlay() async {
    _wantPlay = true;
    _playInterrupted = false;
    if (player == null) return;
    final request = ++_playRequest;
    final granted = await _requestAudioFocus();
    // 等焦点期间暂停、切曲、被打断或关闭了页面，就不再播放
    if (request != _playRequest) return;
    if (granted) return player?.play();
    _wantPlay = false;
    _finishShutdownWaiting();
  }

  Future<void>? onPause() {
    // 主动暂停时让出音频焦点；播放器还没建好时，也取消之后的自动播放
    _releaseAudioFocus();
    return player?.pause();
  }

  // 焦点申请的编号：连着申请时只有最新一次失败才清理
  int _focusRequest = 0;

  /// 开播前申请音频焦点，拿不到（比如通话中）就不播
  Future<bool> _requestAudioFocus() async {
    final handler = audioSessionHandler;
    if (handler == null) return true;
    final request = ++_focusRequest;
    if (await handler.setActive(true, owner: this)) return true;
    // 申请失败时 audio_session 会留着这次申请，之后再申请都直接返回成功，所以要释放；
    // 但期间又申请过的话，焦点可能已经归新申请，不能放掉
    if (request == _focusRequest) handler.setActive(false, owner: this);
    return false;
  }

  void _releaseAudioFocus() {
    _wantPlay = false;
    _playRequest++;
    _playInterrupted = false;
    // 让出焦点后不会再收到 duck 结束
    _restoreDuckedVolume();
    // 返回的视频页已经续播的话，焦点归它，这里不会放掉
    audioSessionHandler?.setActive(false, owner: this);
  }

  @override
  Future<void>? onSeek(Duration duration) {
    onSubtitleSeek(duration);
    _updatePlaybackState(position: duration);
    return player?.seek(duration);
  }

  void _updateCurrItem(DetailItem item) {
    audioItem.value = item;
    _updateMediaItem(item);
  }

  /// Hands [item] to the media card, as the part [subId] names.
  void _updateMediaItem(DetailItem item) {
    // A request that returns after the page left must not bring its card back.
    if (isClosed) return;
    final handler = videoPlayerServiceHandler;
    if (handler == null) return;
    final tag = hashCode.toString();
    // While a page opened from here has the card, the item waits till the card
    // shows this page again.
    if (handler.isShowingPageAbove(tag)) {
      _isCardStale = true;
      return;
    }
    _isCardStale = false;
    handler.onVideoDetailChange(
      item,
      (subId.firstOrNull ?? oid).toInt(),
      tag,
    );
  }

  Future<void> _queryPlayList({
    bool isInit = false,
    bool isLoadPrev = false,
    bool isLoadNext = false,
  }) async {
    final res = await AudioGrpc.audioPlayList(
      id: id,
      oid: isInit ? oid : null,
      subId: isInit ? subId : null,
      itemType: isInit ? itemType : null,
      from: isInit ? from : null,
      next: isLoadPrev
          ? _prev
          : isLoadNext
          ? _next
          : null,
      extraId: extraId,
      order: order,
    );
    if (res case Success(:final response)) {
      if (isInit) {
        late final paginationReply = response.paginationReply;
        _prev = response.reachStart ? null : paginationReply.prev;
        _next = response.reachEnd ? null : paginationReply.next;
        final index = response.list.indexWhere((e) => e.item.oid == oid);
        if (index != -1) {
          this.index = index;
          _updateCurrItem(response.list[index]);
          playlist = response.list;
        }
      } else if (isLoadPrev) {
        _prev = response.reachStart ? null : response.paginationReply.prev;
        if (response.list.isNotEmpty) {
          index += response.list.length;
          playlist?.insertAll(0, response.list);
        }
      } else if (isLoadNext) {
        _next = response.reachEnd ? null : response.paginationReply.next;
        if (response.list.isNotEmpty) {
          playlist?.addAll(response.list);
        }
      }
      // Playback may also have started before the item reached the card.
      onPlaylistChanged();
    } else {
      res.toast();
    }
  }

  /// Republishes the playback state, whose previous / next follow the
  /// playlist, while the media card shows this page and not one opened on top.
  void onPlaylistChanged() {
    if (player != null &&
        videoPlayerServiceHandler?.isShowing(hashCode.toString()) == true) {
      _updatePlaybackState();
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void _querySponsorBlock() {
    if (isUgc && enableSponsorBlock) {
      try {
        final bvid = IdUtils.av2bv(oid.toInt());
        final cid = subId.first.toInt();
        querySponsorBlock(bvid: bvid, cid: cid);
      } catch (_) {}
    }
  }

  Future<bool> _queryPlayUrl() async {
    _querySponsorBlock();
    final request = ++_urlRequest;
    // 要换曲了，还在等焦点的上一首就不用再播
    _playRequest++;
    final res = await AudioGrpc.audioPlayUrl(
      itemType: itemType,
      oid: oid,
      subId: subId,
    );
    // 期间又切了别的，这次的结果作废；等地址期间暂停过的，换过去以后也先不播
    if (request != _urlRequest) return false;
    _urlReturned = request;
    if (res case Success(:final response)) {
      if (!_onPlay(response)) _releaseAudioFocusIfStopped();
      return true;
    } else {
      res.toast();
      _releaseAudioFocusIfStopped();
      return false;
    }
  }

  /// 下一个放不了时，已经播完的就别再占着焦点。被打断、停在半路的留着，
  /// 打断结束后还能接着放
  void _releaseAudioFocusIfStopped() {
    if (isPlaying()) return;
    if (_playInterrupted && !(player?.state.completed ?? true)) return;
    _releaseAudioFocus();
    _finishShutdownWaiting();
  }

  /// 定时关闭在等当前这一首播完的话，已经没有可播的了，现在就执行
  void _finishShutdownWaiting() {
    if (shutdownTimerService.isWaiting) shutdownTimerService.handleWaiting();
  }

  /// 打开了可以播放的媒体时返回 true
  bool _onPlay(PlayURLResp data) {
    final PlayInfo? playInfo = data.playerInfo.values.firstOrNull;
    if (playInfo != null) {
      http_model.Volume? volume;
      if (playInfo.hasVolume()) {
        final volumeInfo = playInfo.volume;
        volume = http_model.Volume(
          measuredI: volumeInfo.measuredI,
          measuredLra: volumeInfo.measuredLra,
          measuredTp: volumeInfo.measuredTp,
          measuredThreshold: volumeInfo.measuredThreshold,
          targetOffset: volumeInfo.targetOffset,
          targetI: volumeInfo.targetI,
          targetTp: volumeInfo.targetTp,
        );
      }
      if (playInfo.hasPlayDash()) {
        final playDash = playInfo.playDash;
        final audios = playDash.audio;
        if (audios.isEmpty) {
          return false;
        }
        position.value = 0;
        final audio = audios.findTargetMedia((e) => e.id, cacheAudioQa);
        _onOpenMedia(VideoUtils.getCdnUrl(audio.playUrls), volume: volume);
        return true;
      } else if (playInfo.hasPlayUrl()) {
        final playUrl = playInfo.playUrl;
        final durls = playUrl.durl;
        if (durls.isEmpty) {
          return false;
        }
        final durl = durls.first;
        position.value = 0;
        _onOpenMedia(VideoUtils.getCdnUrl(durl.playUrls), volume: volume);
        return true;
      }
    }
    return false;
  }

  Future<void> _onOpenMedia(
    String url, {
    String ua = Constants.userAgentApp,
    String? referer,
    http_model.Volume? volume,
  }) async {
    // The subtitles follow what plays from now on, whichever way it came:
    // its address asked for, or handed over by the video page.
    subtitleTarget = itemType == 1 && subId.isNotEmpty
        ? (oid.toInt(), subId.first.toInt())
        : null;
    onSubtitleTargetChanged();
    await _initPlayerIfNeeded();
    final extras = audioFilterExtras(volume);
    player
      ?..setMediaHeader(
        userAgent: ua,
        // mpv cannot clear referer option
        headers: {'Referer': ?referer},
      )
      ..open(Media(url, start: _start, extras: extras), play: false);
    _start = null;
    // A late answer must not start playing under a page opened from here that
    // has the card: that page's sound would mix with this, out of the card's
    // reach.
    if (videoPlayerServiceHandler?.isShowingPageAbove(hashCode.toString()) ==
        true) {
      _wantPlay = false;
    } else if (_wantPlay) {
      onPlay();
    }
  }

  PlayerStatus _playerStatus = .paused;
  void _updatePlaybackState({Duration? position, String? debugLabel}) {
    // A page opened from here that has the card keeps its own state there.
    if (videoPlayerServiceHandler?.isShowingPageAbove(hashCode.toString()) ==
        true) {
      return;
    }
    videoPlayerServiceHandler?.onUpdateState(
      _playerStatus,
      false,
      false,
      position: position ?? player!.state.position,
      speed: speed,
      canSkip: (playlist?.length ?? 0) > 1,
      debugLabel: debugLabel,
    );
  }

  Future<void> _initPlayerIfNeeded() async {
    if (_hasInit) return;
    _hasInit = true;
    assert(player == null, _subscriptions = null);
    final session = audioSessionHandler == null
        ? null
        : await AudioSession.instance;
    player = await Player.create(
      configuration: PlayerConfiguration(
        options: {
          if (Platform.isAndroid) 'ao': Pref.audioOutput,
          'volume': PlatformUtils.isDesktop
              ? (desktopVolume.value * 100).toString()
              : Pref.playerVolume.toString(),
          ...Pref.initBuffer(),
        },
      ),
    );
    if (isClosed) {
      player!.dispose();
      player = null;
      return;
    }
    final stream = player!.stream;
    _subscriptions = [
      stream.position.listen((position) {
        updateSubtitlePosition(position);
        if (isDragging) return;
        final seconds = position.inSeconds;
        if (seconds != this.position.value) {
          if (seconds == 0 && _playerStatus.isPlaying) {
            _updatePlaybackState(position: position);
          }
          this.position.value = seconds;
          _videoDetailController?.playedTime = position;
        }
      }),
      stream.duration.listen((duration) {
        this.duration.value = duration.inSeconds;
      }),
      stream.playing.listen((playing) {
        updateSubtitlePlaying(playing);
        if (playing) {
          animController.forward();
          _playerStatus = .playing;
          _stopStatusTimer();
          // The card can lose this page's item, such as when the last video
          // page, opened from here with 看MV, closes and clears it: playing
          // hands the item back.
          if (videoPlayerServiceHandler?.isShowing(hashCode.toString()) ==
              false) {
            if (audioItem.value case final item?) _updateMediaItem(item);
          }
          _updatePlaybackState();
        } else {
          animController.reverse();
          _playerStatus = .paused;
          _startStatusTimer();
        }
      }),
      stream.buffering.listen((bool buffering) {
        updateSubtitleBuffering(buffering);
        if (!_playerStatus.isCompleted) {
          _stopStatusTimer();
          _updatePlaybackState();
        }
      }),
      stream.completed.listen((completed) {
        _videoDetailController?.playedTime = player!.state.duration;
        if (completed) {
          _playerStatus = .completed;
          _startStatusTimer();
          // 播完不再接着放时让出音频焦点。定时关闭在等这一首播完的话先执行它，
          // 正在切的那首也就不再自动播放
          if (shutdownTimerService.isWaiting) {
            _releaseAudioFocus();
            shutdownTimerService.handleWaiting();
          } else if (!_switchingTrack) {
            // 点了别的一首、地址还没回来时，播完的是旧的那首，接着放新的就行
            switch (playMode.value) {
              case PlayRepeat.pause:
                _releaseAudioFocus();
                break;
              case PlayRepeat.listOrder:
                if (!playNext(nextPart: true)) _releaseAudioFocus();
                break;
              case PlayRepeat.singleCycle:
                onPlay();
                break;
              case PlayRepeat.listCycle:
                if (!playNext(nextPart: true)) {
                  if (index != null && index != 0 && playlist != null) {
                    playIndex(0);
                  } else {
                    onPlay();
                  }
                }
                break;
              case PlayRepeat.autoPlayRelated:
                _releaseAudioFocus();
                break;
            }
          }
        }
      }),
      if (session != null) ...[
        session.interruptionEventStream.listen(_onInterruption),
        // 耳机拔出暂停；被打断后等着恢复的、正在切下一首的，也都不再播放，
        // 免得从扬声器放出来
        session.becomingNoisyEventStream.listen((_) => onPause()),
      ],
    ];
  }

  void _onInterruption(AudioInterruptionEvent event) {
    final player = this.player;
    if (player == null) return;
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (!player.state.playing) return;
          _volumeBeforeDuck ??= player.state.volume;
          player.setVolume(_volumeBeforeDuck! * 0.5);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // 安卓上的 unknown 是永久失去焦点，不会再有结束（iOS 的打断开始都是 unknown）
          final canResume =
              event.type == AudioInterruptionType.pause || !Platform.isAndroid;
          // 在放，或者正等着下一首接着放，才算被打断
          if (!_wantPlay) {
            // 临时打断后又永久失去了焦点，就不会再恢复了
            if (_playInterrupted && !canResume) {
              _playInterrupted = false;
              _finishShutdownWaiting();
            }
            return;
          }
          _wantPlay = false;
          _playRequest++;
          // 被打断时保留音频焦点，打断结束后才能恢复
          _playInterrupted = canResume;
          // 降低音量后又被暂停时，不一定还会收到 duck 结束
          _restoreDuckedVolume();
          player.pause();
          if (!canResume) _finishShutdownWaiting();
      }
    } else {
      _restoreDuckedVolume();
      if (_playInterrupted && event.type == AudioInterruptionType.pause) {
        _wantPlay = true;
        // 正在切曲、或者在等下一首的地址时不用播，地址回来就会接着放
        if (!player.state.completed && !_switchingTrack) player.play();
      }
      _playInterrupted = false;
    }
  }

  void _restoreDuckedVolume() {
    if (_volumeBeforeDuck case final volume?) {
      _volumeBeforeDuck = null;
      player?.setVolume(volume);
    }
  }

  Future<void>? playOrPause() {
    if (isPlaying()) return onPause();
    return onPlay();
  }

  bool playPrev() {
    if (index != null && playlist != null && player != null) {
      final prev = index! - 1;
      if (prev >= 0) {
        playIndex(prev);
        return true;
      }
    }
    return false;
  }

  bool playNext({bool nextPart = false}) {
    if (nextPart) {
      if (audioItem.value case DetailItem(:final parts)) {
        if (parts.length > 1) {
          final subId = this.subId.firstOrNull;
          final nextIndex = parts.indexWhere((e) => e.subId == subId) + 1;
          if (nextIndex != 0 && nextIndex < parts.length) {
            final nextPart = parts[nextIndex];
            oid = nextPart.oid;
            this.subId = [nextPart.subId];
            _queryPlayUrl().then((res) {
              if (res) {
                _videoDetailController = null;
                if (audioItem.value case final item?) _updateMediaItem(item);
              }
            });
            return true;
          }
        }
      }
    }
    if (index != null && playlist != null && player != null) {
      final next = index! + 1;
      if (next < playlist!.length) {
        if (next == playlist!.length - 1 && _next != null) {
          _queryPlayList(isLoadNext: true);
        }
        playIndex(next);
        return true;
      }
    }
    return false;
  }

  void playIndex(int index, {List<Int64>? subId}) {
    if (index == this.index && subId == null) return;
    _wantPlay = true;
    this.index = index;
    final audioItem = playlist![index];
    final item = audioItem.item;
    oid = item.oid;
    this.subId =
        subId ??
        (item.subId.isNotEmpty ? item.subId : [audioItem.parts.first.subId]);
    itemType = item.itemType;
    _queryPlayUrl().then((res) {
      if (res) {
        _videoDetailController = null;
        _updateCurrItem(audioItem);
      }
    });
  }

  Future<void> loadPrev(BuildContext context) async {
    if (_prev == null) return;
    final length = playlist!.length;
    await _queryPlayList(isLoadPrev: true);
    if (length != playlist!.length && context.mounted) {
      (context as Element).markNeedsBuild();
    }
  }

  Future<void> loadNext(BuildContext context) async {
    if (_next == null) return;
    final length = playlist!.length;
    await _queryPlayList(isLoadNext: true);
    if (length != playlist!.length && context.mounted) {
      (context as Element).markNeedsBuild();
    }
  }

  void onChangeOrder(ListOrder value) {
    if (order != value) {
      order = value;
      _queryPlayList(isInit: true);
    }
  }

  @override
  BlockConfigMixin get blockConfig => this;

  @override
  int get currPosInMilliseconds => player?.state.position.inMilliseconds ?? 0;

  @override
  int? get timeLength => player?.state.duration.inMilliseconds ?? 0;

  @override
  Future<void>? seekTo(Duration duration, {required bool isSeek}) =>
      onSeek(duration);

  @override
  bool get autoPlay => true;

  @override
  bool get preInitPlayer => true;

  @override
  void onClose() {
    _stopStatusTimer();
    _mediaItemSubscription?.cancel();
    shutdownTimerService
      ..onPause = null
      ..isPlaying = null
      ..reset();
    _unbindMediaControls();
    videoPlayerServiceHandler
      ?..onVideoDetailDispose(hashCode.toString())
      ..clearIfNeeded()
      ..onPageClose(hashCode.toString());
    _subscriptions?.forEach((e) => e.cancel());
    _subscriptions?.clear();
    _subscriptions = null;
    _releaseAudioFocus();
    player?.dispose();
    player = null;
    animController.dispose();
    super.onClose();
  }
}

extension on DashItem {
  Iterable<String> get playUrls sync* {
    yield baseUrl;
    yield* backupUrl;
  }
}

extension on ResponseUrl {
  Iterable<String> get playUrls sync* {
    yield url;
    yield* backupUrl;
  }
}
