import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/utils/subtitle_utils.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

SubtitleLine _line(int fromMs, int toMs, [String content = '字幕']) =>
    SubtitleLine(from: _ms(fromMs), to: _ms(toMs), content: content);

/// The line a linear scan finds, to check the binary search against.
int _scan(List<SubtitleLine> lines, Duration position) =>
    lines.lastIndexWhere((e) => e.from <= position);

Subtitle _subtitle(String lan, {bool isAi = false}) =>
    Subtitle(lan: lan, lanDoc: lan, isAi: isAi);

void main() {
  group('SubtitleLine.fromJson', () {
    test('reads the times in seconds, whole or not', () {
      final line = SubtitleLine.fromJson({
        'from': 1,
        'to': 2.53,
        'sid': 1,
        'location': 2,
        'content': '大家好',
        'music': 0.0,
      });
      expect(line.from, _ms(1000));
      expect(line.to, _ms(2530));
      expect(line.content, '大家好');
    });

    test('trims the content, and reads a missing one as empty', () {
      expect(
        SubtitleLine.fromJson({'from': 0, 'to': 1, 'content': ' 你好\n'}).content,
        '你好',
      );
      expect(SubtitleLine.fromJson({'from': 0, 'to': 1}).content, '');
    });
  });

  group('SubtitleUtils.parseLines', () {
    test('keeps the lines in time order, ties in the order given', () {
      final lines = SubtitleUtils.parseLines([
        {'from': 3.0, 'to': 4.0, 'content': '三'},
        {'from': 1.0, 'to': 2.0, 'content': '一'},
        {'from': 3.0, 'to': 5.0, 'content': '三之二'},
        {'from': 2.0, 'to': 3.0, 'content': '二'},
      ]);
      expect(lines.map((e) => e.content), ['一', '二', '三', '三之二']);
    });

    test('drops empty lines and what is not a line', () {
      final lines = SubtitleUtils.parseLines([
        {'from': 0.5, 'to': 1.0, 'content': '  '},
        'not a line',
        null,
        {'from': 1.0, 'to': 2.0, 'content': '留下'},
      ]);
      expect(lines.map((e) => e.content), ['留下']);
    });

    test('an empty body has no lines', () {
      expect(SubtitleUtils.parseLines([]), isEmpty);
    });
  });

  group('SubtitleUtils.lineIndexAt', () {
    final lines = [
      _line(1000, 2000),
      _line(2000, 3500),
      // a pause from 3.5s to 6s
      _line(6000, 7000),
    ];

    test('no line is current before the first one starts', () {
      expect(SubtitleUtils.lineIndexAt(lines, .zero), -1);
      expect(SubtitleUtils.lineIndexAt(lines, _ms(999)), -1);
    });

    test('a line is current from the moment it starts', () {
      expect(SubtitleUtils.lineIndexAt(lines, _ms(1000)), 0);
      expect(SubtitleUtils.lineIndexAt(lines, _ms(1999)), 0);
      expect(SubtitleUtils.lineIndexAt(lines, _ms(2000)), 1);
    });

    test('a line stays current through the pause after it', () {
      expect(SubtitleUtils.lineIndexAt(lines, _ms(3500)), 1);
      expect(SubtitleUtils.lineIndexAt(lines, _ms(5999)), 1);
      expect(SubtitleUtils.lineIndexAt(lines, _ms(6000)), 2);
    });

    test('the last line stays current after the end', () {
      expect(SubtitleUtils.lineIndexAt(lines, const Duration(hours: 1)), 2);
    });

    test('no line is current without lines', () {
      expect(SubtitleUtils.lineIndexAt(const [], _ms(1000)), -1);
    });

    test('overlapping lines: the one started last is current', () {
      final overlapping = [_line(0, 5000), _line(1000, 2000)];
      expect(SubtitleUtils.lineIndexAt(overlapping, _ms(1500)), 1);
      expect(SubtitleUtils.lineIndexAt(overlapping, _ms(3000)), 1);
    });

    test('finds the same line as a scan, all along a long video', () {
      final long = [
        for (var i = 0; i < 1000; i++) _line(i * 2300, i * 2300 + 1800),
      ];
      for (var ms = 0; ms < 2400000; ms += 137) {
        expect(
          SubtitleUtils.lineIndexAt(long, _ms(ms)),
          _scan(long, _ms(ms)),
          reason: 'at ${ms}ms',
        );
      }
    });
  });

  group('SubtitleUtils.pickSubtitle', () {
    final subtitles = [
      _subtitle('zh-CN'),
      _subtitle('ai-zh', isAi: true),
      _subtitle('en-US'),
      _subtitle('ai-ja', isAi: true),
    ];

    test('none to pick from', () {
      expect(SubtitleUtils.pickSubtitle(const [], 'zh-CN'), -1);
    });

    test('the first without a language picked before', () {
      expect(SubtitleUtils.pickSubtitle(subtitles, null), 0);
    });

    test('the language picked before', () {
      expect(SubtitleUtils.pickSubtitle(subtitles, 'ai-zh'), 1);
      expect(SubtitleUtils.pickSubtitle(subtitles, 'en-US'), 2);
    });

    test('else another one of the same language', () {
      // English by AI picked before, this video has an UP's English one
      expect(SubtitleUtils.pickSubtitle(subtitles, 'ai-en'), 2);
      // the UP's Japanese one picked before, this video only has AI's
      expect(SubtitleUtils.pickSubtitle(subtitles, 'ja'), 3);
      // Chinese of another region: the first Chinese one, the UP's
      expect(SubtitleUtils.pickSubtitle(subtitles, 'zh-Hans'), 0);
    });

    test('else the first', () {
      expect(SubtitleUtils.pickSubtitle(subtitles, 'ko'), 0);
    });
  });
}
