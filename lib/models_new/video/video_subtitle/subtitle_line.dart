/// One line in the `body` of a subtitle file: `{from, to, content}`,
/// with the times in seconds.
class SubtitleLine {
  final Duration from;
  final Duration to;
  final String content;

  const SubtitleLine({
    required this.from,
    required this.to,
    required this.content,
  });

  static Duration _seconds(Object? value) => Duration(
    microseconds: (((value as num?) ?? 0) * Duration.microsecondsPerSecond)
        .round(),
  );

  factory SubtitleLine.fromJson(Map<String, dynamic> json) => SubtitleLine(
    from: _seconds(json['from']),
    to: _seconds(json['to']),
    content: (json['content'] as String?)?.trim() ?? '',
  );
}
