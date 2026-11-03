import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:flutter/foundation.dart';

/// Calls [shown] once [player] shows the first frame of the page's video,
/// [cid] as it is then, which a part picked on the page changes, or fails to
/// load it, and returns what stops watching. The player is shared
/// with the video pages below, which may still be playing another video.
VoidCallback watchFirstFrame(
  PlPlayerController player, {
  required ValueGetter<int> cid,
  required VoidCallback shown,
}) {
  var watching = true;
  StreamSubscription<DataStatus>? loading;
  late final ValueChanged<Duration> onPosition;
  void stop() {
    watching = false;
    loading?.cancel();
    player.removePositionListener(onPosition);
  }

  onPosition = (_) {
    // Still this video: a page opened over this one may have taken the
    // player for its own meanwhile.
    if (watching &&
        player.cid == cid() &&
        player.dataStatus.loaded &&
        player.playerStatus.isPlaying) {
      watching = false;
      // The player is going through its listeners: one leaving now would
      // change them under it.
      scheduleMicrotask(() {
        stop();
        shown();
      });
    }
  };

  void check() {
    if (!watching || player.cid != cid()) {
      return;
    }
    if (player.dataStatus.error) {
      stop();
      shown();
    } else if (player.dataStatus.loaded) {
      loading?.cancel();
      // A player the pages below opened showed its first frame long since:
      // its first position played on this video tells, then.
      (player.videoController?.waitUntilFirstFrameRendered ?? Future.value())
          .then((_) {
            if (watching) {
              player.addPositionListener(onPosition);
            }
          });
    }
  }

  loading = player.dataStatus.listen((_) => check());
  check();
  return stop;
}
