import 'package:PiliPlus/utils/path_utils.dart';
import 'package:path/path.dart' as path;

sealed class DataSource {
  final String videoSource;
  final String? audioSource;

  DataSource({
    required this.videoSource,
    required this.audioSource,
  });
}

class NetworkSource extends DataSource {
  NetworkSource({
    required super.videoSource,
    required super.audioSource,
  });

  /// When the CDN stops serving these links: the earliest `deadline` (Unix
  /// seconds) in them, as Bilibili signs its play links for about two hours.
  /// Null when none carries one.
  late final DateTime? expiresAt = () {
    int? earliest;
    for (final source in [videoSource, ?audioSource]) {
      for (final match in _deadline.allMatches(source)) {
        final deadline = int.parse(match[1]!);
        if (earliest == null || deadline < earliest) earliest = deadline;
      }
    }
    return earliest == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(earliest * 1000);
  }();

  // An edl:// source holds several links, so every one is read.
  static final _deadline = RegExp(r'[?&]deadline=(\d+)');
}

class FileSource extends DataSource {
  final String dir;
  final bool isMp4;

  FileSource({
    required this.dir,
    required this.isMp4,
    required bool hasDashAudio,
    required String typeTag,
  }) : super(
         videoSource: path.join(
           dir,
           typeTag,
           isMp4 ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
         ),
         audioSource: isMp4 || !hasDashAudio
             ? null
             : path.join(dir, typeTag, PathUtils.audioNameType2),
       );
}

/// When a source's links run out, judged by the device's clock against the
/// deadline Bilibili signs them with, [margin] early: a paused player's
/// connections close in that time, and the links can't open new ones once
/// expired.
///
/// A source that already looks expired as it opens, as on a phone whose clock
/// runs hours ahead, is never judged expired, so that it isn't opened afresh
/// over and over.
class SourceExpiry {
  SourceExpiry(DataSource source, DateTime openedAt)
    : _expiresAt = switch (source) {
        NetworkSource(:final expiresAt?)
            when openedAt.isBefore(expiresAt.subtract(margin)) =>
          expiresAt,
        _ => null,
      };

  static const margin = Duration(minutes: 3);

  final DateTime? _expiresAt;

  bool isExpiredAt(DateTime now) =>
      _expiresAt != null && !now.isBefore(_expiresAt.subtract(margin));
}
