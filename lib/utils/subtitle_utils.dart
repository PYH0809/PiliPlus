import 'dart:math' as math;

import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';

import 'package:collection/collection.dart' show IterableExtension, mergeSort;

enum SubtitleFormat implements EnumWithLabel {
  json('JSON'),
  vtt('WEBVTT'),
  srt('SRT');

  @override
  final String label;
  const SubtitleFormat(this.label);
}

abstract final class SubtitleUtils {
  static String _vttTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final sms = seconds.toStringAsFixed(3).padLeft(6, '0');
    return "$h:$m:$sms";
  }

  static String json2Vtt(List list) {
    final sb = StringBuffer('WEBVTT\n\n')
      ..writeAll(
        list.map(
          (item) =>
              '${_vttTimecode(item['from'])} --> ${_vttTimecode(item['to'])}\n${item['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static String _srtTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final s = seconds.toInt();
    final ms = ((seconds - s) * 1000).round().toString().padLeft(3, '0');
    return '$h:$m:${s.toString().padLeft(2, '0')},$ms';
  }

  static String json2Srt(List list) {
    final sb = StringBuffer()
      ..writeAll(
        list.mapIndexed(
          (i, e) =>
              '${i + 1}\n${_srtTimecode(e['from'])} --> ${_srtTimecode(e['to'])}\n${e['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  /// The lines of a subtitle `body` in time order, without the empty ones.
  static List<SubtitleLine> parseLines(List body) {
    final lines = <SubtitleLine>[
      for (final item in body)
        if (item is Map<String, dynamic>) SubtitleLine.fromJson(item),
    ]..removeWhere((e) => e.content.isEmpty);
    mergeSort(lines, compare: (a, b) => a.from.compareTo(b.from));
    return lines;
  }

  /// A pause this long or longer between lines, or before the first, is an
  /// interlude: the line before it dims, and dots wait for the next one.
  static const interlude = Duration(seconds: 7);

  /// The last line that has started at [position], -1 before the first.
  static int lastStartedAt(List<SubtitleLine> lines, Duration position) {
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (lines[mid].from <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }

  /// The line lit at [position]: the last one that has started, and it stays
  /// lit through a short pause after it. -1 before the first, in an
  /// [interlude] and after the last.
  static int lineIndexAt(List<SubtitleLine> lines, Duration position) {
    final index = lastStartedAt(lines, position);
    if (index == -1) return -1;
    final line = lines[index];
    if (position < line.to) return index;
    if (index + 1 == lines.length) return -1;
    return lines[index + 1].from - line.to >= interlude ? -1 : index;
  }

  /// The [interlude] before line [index]: from the end of the line before,
  /// or the start, to its own. Null when the pause is shorter.
  static ({Duration start, Duration end})? interludeBefore(
    List<SubtitleLine> lines,
    int index,
  ) {
    final start = index == 0 ? Duration.zero : lines[index - 1].to;
    final end = lines[index].from;
    return end - start >= interlude ? (start: start, end: end) : null;
  }

  /// The [interlude] [position] is in, and the line it waits for.
  static ({int next, Duration start, Duration end})? interludeAt(
    List<SubtitleLine> lines,
    Duration position,
  ) {
    final next = lastStartedAt(lines, position) + 1;
    if (next >= lines.length) return null;
    final pause = interludeBefore(lines, next);
    if (pause == null || position < pause.start) return null;
    return (next: next, start: pause.start, end: pause.end);
  }

  /// How long the list takes to move on to line [index]: 480 ms when it
  /// starts 200 ms or less after the line before it, 750 ms for 750 ms or
  /// more, and in between in proportion. The gap is in real time, as played
  /// at [rate]; the move takes as long at any rate.
  static Duration moveTo(
    List<SubtitleLine> lines,
    int index, {
    double rate = 1,
  }) {
    if (index <= 0) return const Duration(milliseconds: 750);
    final gap =
        (lines[index].from - lines[index - 1].from).inMilliseconds / rate;
    final ms = gap <= 200
        ? 480
        : gap >= 750
        ? 750
        : 480 + (gap - 200) * 270 ~/ 550;
    return Duration(milliseconds: ms);
  }

  /// Where the list heads at [position]: the line lit, and the next one as
  /// soon as moving there would land just as it starts, played at [rate],
  /// though never before the line before it starts; in an interlude, the dots
  /// above the line it waits for. -1 without lines.
  static ({int index, bool dots}) targetAt(
    List<SubtitleLine> lines,
    Duration position, {
    double rate = 1,
  }) {
    if (lines.isEmpty) return (index: -1, dots: false);
    if (interludeAt(lines, position) case (:final next, start: _, end: _)) {
      return (index: next, dots: true);
    }
    final index = lastStartedAt(lines, position);
    final next = index + 1;
    if (next < lines.length) {
      // The move's time, in the media's.
      final early = lines[next].from - moveTo(lines, next, rate: rate) * rate;
      final earliest = index == -1 ? Duration.zero : lines[index].from;
      if (position >= (early > earliest ? early : earliest)) {
        return (index: next, dots: false);
      }
    }
    return (index: math.max(index, 0), dots: false);
  }

  /// Which of [subtitles] to show: the language [lan] picked last time, else
  /// another one of the same language, else the first. -1 when there are none.
  static int pickSubtitle(List<Subtitle> subtitles, String? lan) {
    if (subtitles.isEmpty) return -1;
    if (lan != null) {
      final index = subtitles.indexWhere((e) => e.lan == lan);
      if (index != -1) return index;
      final base = _baseLan(lan);
      final sameBase = subtitles.indexWhere((e) => _baseLan(e.lan) == base);
      if (sameBase != -1) return sameBase;
    }
    return 0;
  }

  /// `zh` for `zh-CN` and for the AI subtitle `ai-zh`.
  static String _baseLan(String lan) {
    if (lan.startsWith('ai-')) lan = lan.substring(3);
    final index = lan.indexOf('-');
    return index == -1 ? lan : lan.substring(0, index);
  }
}
