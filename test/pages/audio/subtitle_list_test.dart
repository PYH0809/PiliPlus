import 'dart:ui' show PointerDeviceKind;

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/pages/audio/subtitle/lyrics_list.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_mixin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class _Audio extends GetxController with AudioSubtitleMixin {
  @override
  (int, int)? subtitleTarget;

  Duration? seekedTo;
  bool playing = true;

  @override
  Future<void>? onSeek(Duration duration) {
    seekedTo = duration;
    return null;
  }

  @override
  Future<void>? onPlay() {
    playing = true;
    updateSubtitlePlaying(true);
    return null;
  }

  @override
  bool isPlaying() => playing;
}

Duration _s(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

/// A line every 2 seconds from 1 second in, each 1.5 seconds long.
final _lines = [
  for (var i = 0; i < 60; i++)
    SubtitleLine(
      from: _s(i * 2 + 1),
      to: _s(i * 2 + 2.5),
      content: 'line $i',
    ),
];

const _height = 600.0;

Future<_Audio> _pumpList(
  WidgetTester tester, {
  List<SubtitleLine>? lines,
  Duration? at,
  bool playing = true,
  // Dots move on every frame through an interlude.
  bool settle = true,
}) async {
  final audio = _Audio()
    ..playing = playing
    ..updateSubtitlePlaying(playing)
    ..subtitleLines.value = Success(lines ?? _lines)
    ..updateSubtitlePosition(at ?? .zero);
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: _height,
            child: AudioSubtitleList(controller: audio),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  return audio;
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

double _alphaOf(WidgetTester tester, String text) =>
    _styleOf(tester, text).color!.a;

double _scaleOf(WidgetTester tester, String text) => tester
    .widget<Transform>(
      find
          .ancestor(of: find.text(text), matching: find.byType(Transform))
          .first,
    )
    .transform
    .storage[0];

/// The blur over the line, 0 without one.
double _blurOf(WidgetTester tester, String text) {
  final filtered = tester.widget<ImageFiltered>(
    find.ancestor(of: find.text(text), matching: find.byType(ImageFiltered)),
  );
  if (!filtered.enabled) return 0;
  // ImageFilter.blur(sigmaX, sigmaY, mode)
  final sigma = RegExp(
    r'blur\(([\d.]+)',
  ).firstMatch(filtered.imageFilter.toString())!.group(1)!;
  return double.parse(sigma);
}

/// Where the line's top sits, as a share of the list's height.
double _topOf(WidgetTester tester, String text) {
  final list = tester.getRect(find.byType(AudioSubtitleList));
  return (tester.getTopLeft(find.text(text)).dy - list.top) / list.height;
}

/// Plays on from [from] to [to] in steps of [step], as the player tells it.
Future<void> _play(
  WidgetTester tester,
  _Audio audio,
  Duration from,
  Duration to, {
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var at = from; at <= to; at += step) {
    audio.updateSubtitlePosition(at);
    await tester.pump(step);
  }
}

void main() {
  testWidgets('says there are no subtitles', (tester) async {
    final audio = _Audio()..subtitleLines.value = const Success([]);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: AudioSubtitleList(controller: audio)),
      ),
    );
    expect(find.text('暂无字幕'), findsOneWidget);
  });

  test('a page that is not a video has no subtitles', () {
    final audio = _Audio()..toggleSubtitle();
    expect(audio.showSubtitle.value, isTrue);
    expect(audio.subtitleLines.value, const Success<List<SubtitleLine>>([]));
  });

  testWidgets('34 sp bold, the current line lit and the rest dim and small', (
    tester,
  ) async {
    await _pumpList(tester, at: _lines[3].from);
    final style = _styleOf(tester, 'line 3');
    expect(style.fontSize, 34);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.height, 1.2);
    expect(style.color!.r, 1);
    expect(_alphaOf(tester, 'line 3'), closeTo(0.94, 1e-3));
    expect(_alphaOf(tester, 'line 4'), closeTo(0.18, 1e-3));
    expect(_scaleOf(tester, 'line 3'), closeTo(1, 1e-3));
    expect(_scaleOf(tester, 'line 4'), closeTo(0.98, 1e-3));
  });

  testWidgets('Latin lines are tracked tighter, Chinese ones not', (
    tester,
  ) async {
    await _pumpList(
      tester,
      lines: [
        SubtitleLine(from: _s(1), to: _s(2), content: 'Never gonna'),
        SubtitleLine(from: _s(3), to: _s(4), content: '永不放弃你'),
      ],
    );
    expect(
      _styleOf(tester, 'Never gonna').letterSpacing,
      closeTo(-0.68, 1e-9),
    );
    expect(_styleOf(tester, '永不放弃你').letterSpacing, 0);
  });

  testWidgets('the lines blur 1.5 dp a line from the current, up to 6', (
    tester,
  ) async {
    await _pumpList(tester, at: _lines[2].from);
    expect(_blurOf(tester, 'line 2'), 0);
    expect(_blurOf(tester, 'line 1'), closeTo(1.5, 1e-3));
    expect(_blurOf(tester, 'line 3'), closeTo(1.5, 1e-3));
    expect(_blurOf(tester, 'line 4'), closeTo(3, 1e-3));
    expect(_blurOf(tester, 'line 5'), closeTo(4.5, 1e-3));
    expect(_blurOf(tester, 'line 6'), closeTo(6, 1e-3));
    expect(_blurOf(tester, 'line 7'), closeTo(6, 1e-3));
  });

  testWidgets('paused, every line is at full size', (tester) async {
    await _pumpList(tester, at: _lines[3].from, playing: false);
    expect(_scaleOf(tester, 'line 4'), closeTo(1, 1e-3));
    expect(_alphaOf(tester, 'line 4'), closeTo(0.18, 1e-3));
  });

  testWidgets('the current line rests with its top 8% down the list', (
    tester,
  ) async {
    await _pumpList(tester, at: _lines[10].from);
    expect(_topOf(tester, 'line 10'), closeTo(0.08, 0.002));
  });

  testWidgets('before the first line, it waits at the anchor, dim', (
    tester,
  ) async {
    final audio = await _pumpList(tester);
    expect(audio.subtitleLine.value, -1);
    expect(_topOf(tester, 'line 0'), closeTo(0.08, 0.002));
    expect(_alphaOf(tester, 'line 0'), closeTo(0.18, 1e-3));
  });

  testWidgets('it moves on early, to land as the next line starts', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[5].from);
    final next = _lines[6].from;
    // 2 seconds apart: a 750 ms move, so it is still at 1 s before
    await _play(tester, audio, _lines[5].from, next - _s(1));
    expect(_topOf(tester, 'line 5'), closeTo(0.08, 0.002));
    await _play(tester, audio, next - _s(0.95), next - _s(0.4));
    // under way
    final midway = _topOf(tester, 'line 6');
    expect(midway, greaterThan(0.09));
    expect(midway, lessThan(_topOf(tester, 'line 5') + 0.3));
    await _play(tester, audio, next - _s(0.35), next);
    expect(audio.subtitleLine.value, 6);
    expect(_topOf(tester, 'line 6'), closeTo(0.08, 0.003));
  });

  testWidgets('at double speed it still lands as the next line starts', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[5].from)
      ..updateSubtitleRate(2);
    final next = _lines[6].from;
    // 100 ms of the media in each 50 ms frame.
    for (var at = _lines[5].from; at <= next; at += _s(0.1)) {
      audio.updateSubtitlePosition(at);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(audio.subtitleLine.value, 6);
    expect(_topOf(tester, 'line 6'), closeTo(0.08, 0.003));
  });

  testWidgets('a speed change on the way still lands as the line starts', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[5].from);
    final next = _lines[6].from;
    // Under way at 1x, from 750 ms before; then twice as fast.
    await _play(tester, audio, next - _s(1), next - _s(0.5));
    audio.updateSubtitleRate(2);
    for (var at = next - _s(0.4); at <= next; at += _s(0.1)) {
      audio.updateSubtitlePosition(at);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(audio.subtitleLine.value, 6);
    expect(_topOf(tester, 'line 6'), closeTo(0.08, 0.002));
  });

  testWidgets('a pause holds a move, and it goes on with the media', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[5].from);
    final next = _lines[6].from;
    await _play(tester, audio, next - _s(1), next - _s(0.5));
    double offset() =>
        tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset;
    audio
      ..playing = false
      ..updateSubtitlePlaying(false);
    await tester.pump();
    final held = offset();
    await tester.pump(const Duration(seconds: 1));
    expect(offset(), held);

    audio
      ..playing = true
      ..updateSubtitlePlaying(true);
    await _play(tester, audio, next - _s(0.45), next);
    expect(_topOf(tester, 'line 6'), closeTo(0.08, 0.003));
  });

  testWidgets('a move that sets off late still lands as its line starts', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[0].from)
      ..updateSubtitleRate(0.5);
    // At half speed it would set off 375 ms before line 1.
    for (var at = _lines[0].from; at <= _s(2.5); at += _s(0.025)) {
      audio.updateSubtitlePosition(at);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(audio.subtitleFocus.value.index, 0);
    // Twice as fast: it sets off now, 250 ms before the line.
    audio.updateSubtitleRate(2);
    expect(audio.subtitleFocus.value.index, 1);
    for (var at = _s(2.6); at <= _lines[1].from; at += _s(0.1)) {
      audio.updateSubtitlePosition(at);
      await tester.pump(const Duration(milliseconds: 50));
    }
    // And a frame, as a ticker starts on the next one.
    await tester.pump(const Duration(milliseconds: 50));
    expect(_topOf(tester, 'line 1'), closeTo(0.08, 0.002));
  });

  testWidgets('a move set off while paused waits for play', (tester) async {
    final audio = await _pumpList(tester, at: _lines[0].from)
      ..updateSubtitleRate(0.5);
    for (var at = _lines[0].from; at <= _s(2.5); at += _s(0.025)) {
      audio.updateSubtitlePosition(at);
      await tester.pump(const Duration(milliseconds: 50));
    }
    audio
      ..playing = false
      ..updateSubtitlePlaying(false);
    await tester.pump();
    double offset() =>
        tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset;
    final paused = offset();
    // Twice as fast moves the focus on, the media standing still.
    audio.updateSubtitleRate(2);
    expect(audio.subtitleFocus.value.index, 1);
    // Frames, as a ticker counts from the first.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(offset(), paused);

    audio
      ..playing = true
      ..updateSubtitlePlaying(true);
    for (var at = _s(2.6); at <= _lines[1].from; at += _s(0.1)) {
      audio.updateSubtitlePosition(at);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(_topOf(tester, 'line 1'), closeTo(0.08, 0.002));
  });

  testWidgets('the rows below set off later, the ones above together', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[5].from);
    final next = _lines[6].from;
    await _play(tester, audio, _lines[5].from, next - _s(0.8));
    // Between lines that stay dim, as a line lit or dimmed changes size.
    double gap(String a, String b) =>
        tester.getTopLeft(find.text(b)).dy - tester.getTopLeft(find.text(a)).dy;
    final rowGap = gap('line 7', 'line 8');
    final aboveGap = gap('line 4', 'line 5');
    await _play(tester, audio, next - _s(0.75), next - _s(0.7));
    // Moving up: line 8, two rows below the focus, lags behind line 7, one.
    expect(gap('line 7', 'line 8'), greaterThan(rowGap + 0.5));
    expect(gap('line 4', 'line 5'), closeTo(aboveGap, 0.01));
    await tester.pumpAndSettle();
    expect(gap('line 7', 'line 8'), closeTo(rowGap, 0.01));
  });

  testWidgets('a seek springs to its line', (tester) async {
    final audio = await _pumpList(tester, at: _lines[3].from);
    audio.updateSubtitlePosition(_lines[30].from + _s(0.2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(audio.subtitleLine.value, 30);
    expect(_topOf(tester, 'line 30'), closeTo(0.08, 0.002));
  });

  testWidgets('tapping a line plays from its start, at once', (tester) async {
    final audio = await _pumpList(tester, at: _lines[2].from, playing: false);
    await tester.tap(find.text('line 6'));
    expect(audio.seekedTo, _lines[6].from);
    expect(audio.playing, isTrue);
    expect(audio.subtitleLine.value, 6);
    await tester.pumpAndSettle();
    expect(_topOf(tester, 'line 6'), closeTo(0.08, 0.002));
    expect(_alphaOf(tester, 'line 6'), closeTo(0.94, 1e-3));
  });

  group('a scroll by hand', () {
    testWidgets('unblurs the lines and dims them evenly', (tester) async {
      await _pumpList(tester, at: _lines[10].from);
      await tester.drag(find.text('line 10'), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(_blurOf(tester, 'line 8'), 0);
      expect(_alphaOf(tester, 'line 8'), closeTo(0.45, 1e-3));
      expect(_alphaOf(tester, 'line 10'), closeTo(0.94, 1e-3));
    });

    testWidgets('goes back at the next line change, not on a timer', (
      tester,
    ) async {
      final audio = await _pumpList(tester, at: _lines[10].from);
      await tester.drag(find.text('line 10'), const Offset(0, 150));
      await tester.pumpAndSettle();
      final dragged = _topOf(tester, 'line 10');
      await tester.pump(const Duration(seconds: 5));
      expect(_topOf(tester, 'line 10'), dragged);

      await _play(tester, audio, _lines[11].from - _s(1), _lines[11].from);
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'line 11'), closeTo(0.08, 0.002));
      expect(_blurOf(tester, 'line 12'), closeTo(1.5, 1e-3));
    });

    testWidgets('not within 500 ms of the scroll ending', (tester) async {
      final audio = await _pumpList(tester, at: _lines[10].from);
      // Ends just before line 11's move would start.
      audio.updateSubtitlePosition(_lines[11].from - _s(0.8));
      await tester.pump();
      await tester.drag(find.text('line 10'), const Offset(0, 150));
      await tester.pump();
      final dragged = _topOf(tester, 'line 10');
      await _play(
        tester,
        audio,
        _lines[11].from - _s(0.75),
        _lines[11].from - _s(0.4),
      );
      expect(audio.subtitleFocus.value.index, 11);
      expect(_topOf(tester, 'line 10'), closeTo(dragged, 0.001));
      // Line 12 then finds it still, and takes it back.
      await _play(tester, audio, _lines[11].from, _lines[12].from);
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'line 12'), closeTo(0.08, 0.002));
    });

    testWidgets('not while a finger holds the list', (tester) async {
      final audio = await _pumpList(tester, at: _lines[10].from);
      await tester.drag(find.text('line 10'), const Offset(0, 150));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(AudioSubtitleList)),
      );
      await tester.pump();
      // A line that stays dim and small, so that only the list moves it.
      final held = _topOf(tester, 'line 14');
      await _play(tester, audio, _lines[11].from - _s(1), _lines[11].from);
      await tester.pump(const Duration(seconds: 1));
      expect(_topOf(tester, 'line 14'), held);

      // Let go: still a moment, then the next line takes it back.
      await finger.up();
      await tester.pump(const Duration(milliseconds: 600));
      await _play(tester, audio, _lines[12].from - _s(1), _lines[12].from);
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'line 12'), closeTo(0.08, 0.002));
    });

    testWidgets('ends at a seek, to where it landed', (tester) async {
      final audio = await _pumpList(tester, at: _lines[10].from);
      await tester.fling(find.text('line 10'), const Offset(0, 1500), 3000);
      await tester.pumpAndSettle();
      expect(find.text('line 30'), findsNothing);

      audio.onSubtitleSeek(_lines[30].from);
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'line 30'), closeTo(0.08, 0.002));
      expect(_blurOf(tester, 'line 31'), closeTo(1.5, 1e-3));
    });

    testWidgets('stays while the new line is out of sight', (tester) async {
      final audio = await _pumpList(tester, at: _lines[10].from);
      await tester.fling(find.text('line 10'), const Offset(0, 1500), 3000);
      await tester.pumpAndSettle();
      expect(find.text('line 11'), findsNothing);
      final top = _topOf(tester, 'line 2');
      await _play(tester, audio, _lines[11].from - _s(1), _lines[11].from);
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'line 2'), top);
    });
  });

  testWidgets('a finger on the list stops a move at once', (tester) async {
    final audio = await _pumpList(tester, at: _lines[10].from);
    audio.updateSubtitlePosition(_lines[20].from);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AudioSubtitleList)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // Line 12, on screen as the move sets off, stays dim and its size still.
    final touched = tester.getTopLeft(find.text('line 12')).dy;
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(find.text('line 12')).dy, touched);
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('line 12')).dy - touched,
      greaterThan(50),
    );
    await gesture.up();
  });

  testWidgets('a mouse wheel stops a move too', (tester) async {
    final audio = await _pumpList(tester, at: _lines[10].from);
    audio.updateSubtitlePosition(_lines[20].from);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(AudioSubtitleList));
    await tester.sendEventToBinding(wheel.hover(center));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -100)));
    await tester.pump();
    final scrolled = tester.getTopLeft(find.text('line 12')).dy;
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(find.text('line 12')).dy, scrolled);
  });

  testWidgets('a focus that comes before its lines does not move the list', (
    tester,
  ) async {
    final audio = await _pumpList(tester, at: _lines[10].from);
    // Another language, still loading, and the focus a line on.
    audio.subtitleLines.value = LoadingState.loading();
    await tester.pump();
    audio.subtitleFocus.value = (index: 11, dots: false);
    await tester.pump();
    expect(tester.takeException(), isNull);

    audio
      ..subtitleLines.value = Success(_lines)
      ..updateSubtitlePosition(_lines[11].from);
    await tester.pumpAndSettle();
    expect(_topOf(tester, 'line 11'), closeTo(Lyrics.anchor, 0.01));
  });

  group('interlude dots', () {
    final dots = find.byWidgetPredicate(
      (widget) =>
          widget is SizedBox &&
          widget.width == Lyrics.dot &&
          widget.height == Lyrics.dot,
    );

    List<SubtitleLine> apart(double gap) => [
      SubtitleLine(from: _s(1), to: _s(2), content: 'before'),
      SubtitleLine(from: _s(2 + gap), to: _s(3 + gap), content: 'after'),
    ];

    testWidgets('show in a pause of 7 seconds', (tester) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      await _play(tester, audio, _s(1.5), _s(3));
      expect(audio.subtitleLine.value, -1);
      expect(dots, findsNWidgets(3));
      // Where the next line will be: the dots at the anchor, the line below.
      final list = tester.getRect(find.byType(AudioSubtitleList));
      final first = tester.getTopLeft(dots.first).dy - list.top;
      expect(first / list.height, closeTo(0.08, 0.03));
      expect(
        tester.getTopLeft(find.text('after')).dy,
        greaterThan(tester.getBottomLeft(dots.first).dy),
      );
      // Gone as the line comes.
      await _play(tester, audio, _s(3), _s(9.2));
      await tester.pumpAndSettle();
      expect(audio.subtitleLine.value, 1);
      expect(dots, findsNothing);
    });

    testWidgets('not in a pause of 6', (tester) async {
      final audio = await _pumpList(tester, lines: apart(6), at: _s(1));
      await _play(tester, audio, _s(1.5), _s(4));
      expect(audio.subtitleLine.value, 0);
      expect(dots, findsNothing);
    });

    testWidgets('before a first line 7 seconds in', (tester) async {
      final audio = await _pumpList(
        tester,
        lines: [SubtitleLine(from: _s(8), to: _s(9), content: 'first')],
        settle: false,
      );
      await _play(tester, audio, .zero, _s(1));
      expect(dots, findsNWidgets(3));
    });

    testWidgets('not with under 910 ms of it left', (tester) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      audio.updateSubtitlePosition(_s(8.2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.subtitleInterlude.value, isNotNull);
      expect(dots, findsNothing);
    });

    testWidgets('hold still, asking for no frames, while paused', (
      tester,
    ) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      await _play(tester, audio, _s(1.5), _s(3));
      expect(dots, findsNWidgets(3));

      audio
        ..playing = false
        ..updateSubtitlePlaying(false);
      // Settles: the clock stopped.
      await tester.pumpAndSettle();
      expect(dots, findsNWidgets(3));

      audio
        ..playing = true
        ..updateSubtitlePlaying(true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(dots, findsNWidgets(3));
    });

    testWidgets('stop with the lines they were in', (tester) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      await _play(tester, audio, _s(1.5), _s(3));
      expect(dots, findsNWidgets(3));

      // The lines asked for again, and none come.
      audio.retrySubtitle();
      expect(audio.subtitleInterlude.value, isNull);
      await tester.pumpAndSettle();
      expect(find.text('暂无字幕'), findsOneWidget);
    });

    testWidgets('hold still while the player buffers', (tester) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      await _play(tester, audio, _s(1.5), _s(3));
      expect(dots, findsNWidgets(3));

      audio.updateSubtitleBuffering(true);
      // Settles: the clock stopped, though it still plays.
      await tester.pumpAndSettle();
      expect(audio.subtitlePlaying.value, isTrue);

      audio.updateSubtitleBuffering(false);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('come in again after a short seek back', (tester) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      audio.updateSubtitlePosition(_s(8.2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(dots, findsNothing);

      // 400 ms back, to 1.2 s before the line.
      audio.onSubtitleSeek(_s(7.8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(dots, findsNWidgets(3));
    });

    testWidgets('come in again after a seek back in the pause', (tester) async {
      final audio = await _pumpList(tester, lines: apart(7), at: _s(1));
      audio.updateSubtitlePosition(_s(8.2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(dots, findsNothing);

      audio.updateSubtitlePosition(_s(3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(dots, findsNWidgets(3));
    });
  });
}
