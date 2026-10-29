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

  /// The line being spoken at [position]: the last one that has started, so
  /// a line stays current through the pause after it. -1 before the first.
  static int lineIndexAt(List<SubtitleLine> lines, Duration position) {
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
