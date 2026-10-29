import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/subtitle_utils.dart';
import 'package:get/get.dart';

/// The subtitles of the video being listened to, shown like lyrics in place
/// of the cover. They are fetched the first time they are shown, and again
/// for each video or part played after that.
mixin AudioSubtitleMixin on GetxController {
  /// The aid and cid of the video playing now, or null when it is not a video.
  (int, int)? get subtitleTarget;

  Future<void>? onSeek(Duration duration);

  Future<void>? onPlay();

  bool isPlaying();

  final RxBool showSubtitle = false.obs;

  /// The languages of the video, see [Subtitle.compareTo] for the order.
  final RxList<Subtitle> subtitles = <Subtitle>[].obs;

  final RxInt subtitleIndex = (-1).obs;

  /// The lines in the chosen language; an empty list when there are none.
  final Rx<LoadingState<List<SubtitleLine>>> subtitleLines =
      Rx<LoadingState<List<SubtitleLine>>>(LoadingState.loading());

  /// The line lit, see [SubtitleUtils.lineIndexAt].
  final RxInt subtitleLine = (-1).obs;

  /// Where the list heads, see [SubtitleUtils.targetAt].
  final Rx<({int index, bool dots})> subtitleFocus = Rx((
    index: -1,
    dots: false,
  ));

  /// The interlude playing, see [SubtitleUtils.interludeAt].
  final Rxn<({int next, Duration start, Duration end})> subtitleInterlude =
      Rxn();

  /// The position as the player last told it.
  final Rx<Duration> subtitlePosition = Rx(.zero);

  final RxBool subtitlePlaying = false.obs;

  /// The playback speed, as the lines' times pass faster or slower.
  final RxDouble subtitleRate = 1.0.obs;

  /// Waiting on data while playing: the position holds still.
  final RxBool subtitleBuffering = false.obs;

  /// Counts the seeks, after which what eases with the position starts over.
  final RxInt subtitleSeeks = 0.obs;

  /// What [subtitleLines] holds or is loading.
  (int, int)? _target;

  /// Bumped for each new request, so a late answer to an old one is dropped.
  int _generation = 0;

  List<List<SubtitleLine>?> _cache = const [];

  Duration _position = .zero;

  void toggleSubtitle() {
    showSubtitle.toggle();
    if (showSubtitle.value) {
      _loadSubtitles();
    }
  }

  /// Call when another video or part starts playing.
  void onSubtitleTargetChanged() {
    if (subtitleTarget == _target) return;
    _generation++;
    _target = null;
    _cache = const [];
    _position = .zero;
    subtitles.clear();
    subtitleIndex.value = -1;
    subtitleLine.value = -1;
    subtitleInterlude.value = null;
    subtitleFocus.value = (index: -1, dots: false);
    subtitlePosition.value = .zero;
    subtitleLines.value = LoadingState.loading();
    if (showSubtitle.value) {
      _loadSubtitles();
    }
  }

  void updateSubtitlePosition(Duration position) {
    _position = position;
    subtitlePosition.value = position;
    if (subtitleLines.value case Success(:final response)) {
      _follow(response);
    }
  }

  void updateSubtitlePlaying(bool playing) => subtitlePlaying.value = playing;

  /// Call as the player seeks to [position].
  void onSubtitleSeek(Duration position) {
    updateSubtitlePosition(position);
    subtitleSeeks.value++;
  }

  void updateSubtitleBuffering(bool buffering) =>
      subtitleBuffering.value = buffering;

  void updateSubtitleRate(double rate) {
    subtitleRate.value = rate;
    if (subtitleLines.value case Success(:final response)) {
      _follow(response);
    }
  }

  /// The lit line first, as the list reads it when its focus moves.
  void _follow(List<SubtitleLine> lines) {
    subtitleLine.value = SubtitleUtils.lineIndexAt(lines, _position);
    subtitleInterlude.value = SubtitleUtils.interludeAt(lines, _position);
    subtitleFocus.value = SubtitleUtils.targetAt(
      lines,
      _position,
      rate: subtitleRate.value,
    );
  }

  /// Seeks to the start of [index], and plays from there.
  void seekToSubtitleLine(int index) {
    if (subtitleLines.value case Success(:final response)) {
      final from = response[index].from;
      onSubtitleSeek(from);
      onSeek(from);
      if (!isPlaying()) {
        onPlay();
      }
    }
  }

  void selectSubtitle(int index) {
    if (index == subtitleIndex.value) return;
    GStorage.setting.put(SettingBoxKey.audioSubtitleLan, subtitles[index].lan);
    _showLines(index, ++_generation);
  }

  void retrySubtitle() {
    if (subtitles.isEmpty) {
      _target = null;
      _loadSubtitles();
    } else {
      _showLines(subtitleIndex.value, ++_generation);
    }
  }

  Future<void> _loadSubtitles() async {
    final target = subtitleTarget;
    if (target == null) {
      _target = null;
      subtitleLines.value = const Success([]);
      return;
    }
    if (target == _target) return;
    _target = target;
    final generation = ++_generation;
    subtitleLines.value = LoadingState.loading();
    final res = await _querySubtitles(target.$1, target.$2);
    if (generation != _generation) return;
    if (res case Success(:final response)) {
      subtitles.value = response;
      _cache = List.filled(response.length, null);
      final index = SubtitleUtils.pickSubtitle(
        response,
        Pref.audioSubtitleLan,
      );
      if (index == -1) {
        subtitleLines.value = const Success([]);
      } else {
        _showLines(index, generation);
      }
    } else if (res case final Error error) {
      // try again the next time they are shown
      _target = null;
      subtitleLines.value = error;
    }
  }

  Future<void> _showLines(int index, int generation) async {
    subtitleIndex.value = index;
    if (_cache[index] case final lines?) {
      _setLines(lines);
      return;
    }
    final url = subtitles[index].subtitleUrl;
    if (url == null || url.isEmpty) {
      _setLines(const []);
      return;
    }
    subtitleLines.value = LoadingState.loading();
    final res = await VideoHttp.subtitleLines(url);
    if (generation != _generation) return;
    if (res case Success(:final response)) {
      _cache[index] = response;
      _setLines(response);
    } else {
      subtitleLines.value = res;
    }
  }

  /// The lines first, so that the focus that follows is on lines the list
  /// has.
  void _setLines(List<SubtitleLine> lines) {
    subtitleLines.value = Success(lines);
    _follow(lines);
  }

  static Future<LoadingState<List<Subtitle>>> _querySubtitles(
    int aid,
    int cid,
  ) async {
    final res = await VideoHttp.playInfo(aid: aid.toString(), cid: cid);
    if (res case final Error error) return error;
    if (res.dataOrNull?.subtitle?.subtitles case final subtitles?
        when subtitles.isNotEmpty) {
      return Success(subtitles);
    }
    // playinfo leaves the subtitles out when logged out, dm view has them
    if (!Accounts.main.isLogin) {
      final res = await DmGrpc.dmView(aid, cid);
      if (res case Success(:final response)) {
        if (response.hasSubtitle()) {
          return Success(
            response.subtitle.subtitles
                .map(
                  (i) => Subtitle(
                    lan: i.lan,
                    lanDoc: i.lanDoc,
                    subtitleUrl: i.subtitleUrl.replaceFirst(
                      RegExp('^https?:'),
                      '',
                    ),
                    isAi: i.type == .AI,
                  ),
                )
                .toList()
              ..sort(),
          );
        }
      } else if (res case final Error error) {
        return error;
      }
    }
    return const Success([]);
  }
}
