import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession session;
  bool _playInterrupted = false;
  bool _volumeDucked = false;

  // 视频被临时打断，打断结束后会接着放；这期间媒体卡片不收走，
  // 不再等的时候（结束、永久失去焦点、让出焦点）卡片重新计时
  bool _videoWaitsToPlayOn = false;
  bool get videoWaitsToPlayOn => _videoWaitsToPlayOn;
  void _setVideoWaitsToPlayOn(bool value) {
    if (_videoWaitsToPlayOn && !value) videoPlayerServiceHandler?.onWaitOver();
    _videoWaitsToPlayOn = value;
  }

  // 最后申请焦点的播放器（视频页或听视频），只有它能让出焦点，
  // 免得一个页面晚到的让出把另一个页面刚拿到的焦点放掉
  Object? _focusOwner;

  Future<bool> setActive(bool active, {Object? owner}) {
    if (active) {
      _focusOwner = owner;
    } else {
      // 降的是视频的音量，视频让出焦点后不会再收到 duck 结束。
      // 别的页面让出时视频可能还在被 duck，不能提前恢复
      if (owner is PlPlayerController) _restoreDuckedVolume();
      if (owner != _focusOwner) return Future.value(true);
      _focusOwner = null;
      // 让出焦点后不会再收到打断结束
      _setVideoWaitsToPlayOn(false);
    }
    return session.setActive(active);
  }

  // 只恢复自己降过的音量：视频暂停时（比如在听视频）不会降，
  // 这时不能翻倍，移动端改的是系统音量
  void _restoreDuckedVolume() {
    if (!_volumeDucked) return;
    _volumeDucked = false;
    PlPlayerController.setVolumeIfExists(
      (PlPlayerController.getVolumeIfExists() ?? 0) * 2,
      showIndicator: false,
    );
  }

  AudioSessionHandler() {
    initSession();
  }

  Future<void> initSession() async {
    session = await AudioSession.instance;
    session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      // final player = PlPlayerController.getInstance();
      if (event.begin) {
        // 安卓上 unknown 的开始是永久失去焦点，不会再放（iOS 的打断开始都是 unknown）
        final canResume =
            event.type != AudioInterruptionType.unknown || !Platform.isAndroid;
        if (!canResume) _setVideoWaitsToPlayOn(false);
        if (playerStatus != PlayerStatus.playing) return;
        // if (!player.playerStatus.playing) return;
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 0.5,
              showIndicator: false,
            );
            // player.setVolume(player.volume.value * 0.5);
            _volumeDucked = true;
            break;
          case AudioInterruptionType.pause:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            _setVideoWaitsToPlayOn(true);
            break;
          case AudioInterruptionType.unknown:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            _setVideoWaitsToPlayOn(canResume);
            // 永久失去焦点，不会再有结束
            _restoreDuckedVolume();
            break;
        }
      } else {
        // duck 后又被暂停时，只会收到一次暂停的结束
        _restoreDuckedVolume();
        switch (event.type) {
          case AudioInterruptionType.duck:
            // player.setVolume(player.volume.value * 2);
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) PlPlayerController.playIfExists();
            //player.play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
        _playInterrupted = false;
        _setVideoWaitsToPlayOn(false);
      }
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      videoPlayerServiceHandler?.onBecomingNoisy();
      PlPlayerController.pauseIfExists();
      // final player = PlPlayerController.getInstance();
      // if (player.playerStatus.playing) {
      //   player.pause();
      // }
    });
  }
}
