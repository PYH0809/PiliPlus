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

    test('the last line dims once it ends', () {
      expect(SubtitleUtils.lineIndexAt(lines, _ms(6999)), 2);
      expect(SubtitleUtils.lineIndexAt(lines, _ms(7000)), -1);
      expect(SubtitleUtils.lineIndexAt(lines, const Duration(hours: 1)), -1);
    });

    test('a line dims for an interlude of 7 seconds, not for 6', () {
      final interlude = [_line(0, 1000), _line(8000, 9000)];
      expect(SubtitleUtils.lineIndexAt(interlude, _ms(999)), 0);
      expect(SubtitleUtils.lineIndexAt(interlude, _ms(1000)), -1);
      expect(SubtitleUtils.lineIndexAt(interlude, _ms(8000)), 1);
      final pause = [_line(0, 1000), _line(7000, 8000)];
      expect(SubtitleUtils.lineIndexAt(pause, _ms(1000)), 0);
      expect(SubtitleUtils.lineIndexAt(pause, _ms(6999)), 0);
    });

    test('no line is current without lines', () {
      expect(SubtitleUtils.lineIndexAt(const [], _ms(1000)), -1);
    });

    test('overlapping lines: the one started last is current', () {
      final overlapping = [
        _line(0, 5000),
        _line(1000, 2000),
        _line(4000, 6000),
      ];
      expect(SubtitleUtils.lineIndexAt(overlapping, _ms(1500)), 1);
      expect(SubtitleUtils.lineIndexAt(overlapping, _ms(3000)), 1);
    });

    test('finds the line last started as a scan, all along a long video', () {
      final long = [
        for (var i = 0; i < 1000; i++) _line(i * 2300, i * 2300 + 1800),
      ];
      for (var ms = 0; ms < 2400000; ms += 137) {
        expect(
          SubtitleUtils.lastStartedAt(long, _ms(ms)),
          _scan(long, _ms(ms)),
          reason: 'at ${ms}ms',
        );
      }
    });
  });

  group('SubtitleUtils.interludeAt', () {
    final lines = [_line(8000, 9000), _line(9500, 10000), _line(20000, 21000)];

    test('before the first line, when it comes 7 seconds or more in', () {
      expect(
        SubtitleUtils.interludeAt(lines, _ms(3000)),
        (next: 0, start: Duration.zero, end: _ms(8000)),
      );
      expect(SubtitleUtils.interludeAt([_line(6000, 7000)], _ms(3000)), isNull);
    });

    test('between lines 7 seconds or more apart, from the end of one', () {
      expect(SubtitleUtils.interludeAt(lines, _ms(9999)), isNull);
      expect(
        SubtitleUtils.interludeAt(lines, _ms(10000)),
        (next: 2, start: _ms(10000), end: _ms(20000)),
      );
      expect(SubtitleUtils.interludeAt(lines, _ms(20000)), isNull);
    });

    test('none after the last line', () {
      expect(SubtitleUtils.interludeAt(lines, _ms(60000)), isNull);
    });
  });

  group('SubtitleUtils.moveTo', () {
    List<SubtitleLine> apart(int ms) => [_line(0, 100), _line(ms, ms + 100)];

    test('480 ms up to 200 ms after the line before, 750 from 750', () {
      expect(SubtitleUtils.moveTo(apart(100), 1), _ms(480));
      expect(SubtitleUtils.moveTo(apart(200), 1), _ms(480));
      expect(SubtitleUtils.moveTo(apart(750), 1), _ms(750));
      expect(SubtitleUtils.moveTo(apart(5000), 1), _ms(750));
    });

    test('in proportion between', () {
      expect(SubtitleUtils.moveTo(apart(475), 1), _ms(615));
    });

    test('by the gap as played at a speed', () {
      expect(SubtitleUtils.moveTo(apart(950), 1, rate: 2), _ms(615));
      expect(SubtitleUtils.moveTo(apart(475), 1, rate: 0.5), _ms(750));
    });
  });

  group('SubtitleUtils.targetAt', () {
    final lines = [_line(1000, 2000), _line(3000, 4000), _line(3300, 3600)];

    test('heads for the next line early, to land as it starts', () {
      // 2 seconds apart: a 750 ms move, from 2.25 s
      expect(SubtitleUtils.targetAt(lines, _ms(2249)), (index: 0, dots: false));
      expect(SubtitleUtils.targetAt(lines, _ms(2250)), (index: 1, dots: false));
    });

    test('sets off by the move played at a speed', () {
      // At 2x a 750 ms move is 1.5 s of the media's: no sooner than line 0
      expect(SubtitleUtils.targetAt(lines, _ms(1499), rate: 2).index, 0);
      expect(SubtitleUtils.targetAt(lines, _ms(1500), rate: 2).index, 1);
      // At 0.5x, 375 ms of it
      expect(SubtitleUtils.targetAt(lines, _ms(2624), rate: 0.5).index, 0);
      expect(SubtitleUtils.targetAt(lines, _ms(2625), rate: 0.5).index, 1);
    });

    test('but not before the line before it starts', () {
      // 300 ms apart, a 529 ms move: no sooner than 3 s
      expect(SubtitleUtils.targetAt(lines, _ms(3000)).index, 2);
      expect(SubtitleUtils.targetAt(lines, _ms(2999)).index, 1);
    });

    test('waits on the first line, and stays on the last', () {
      expect(SubtitleUtils.targetAt(lines, Duration.zero), (
        index: 0,
        dots: false,
      ));
      expect(SubtitleUtils.targetAt(lines, _ms(60000)), (
        index: 2,
        dots: false,
      ));
      expect(SubtitleUtils.targetAt(const [], Duration.zero).index, -1);
    });

    test('rests on the dots of an interlude', () {
      final interlude = [_line(0, 1000), _line(9000, 10000)];
      expect(SubtitleUtils.targetAt(interlude, _ms(500)), (
        index: 0,
        dots: false,
      ));
      expect(SubtitleUtils.targetAt(interlude, _ms(1000)), (
        index: 1,
        dots: true,
      ));
      expect(SubtitleUtils.targetAt(interlude, _ms(8999)), (
        index: 1,
        dots: true,
      ));
      expect(SubtitleUtils.targetAt(interlude, _ms(9000)), (
        index: 1,
        dots: false,
      ));
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
