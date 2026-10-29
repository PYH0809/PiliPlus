import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_mixin.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class _Audio extends GetxController with AudioSubtitleMixin {
  @override
  (int, int)? subtitleTarget;

  Duration? seekedTo;
  bool playing = false;

  @override
  Future<void>? onSeek(Duration duration) {
    seekedTo = duration;
    return null;
  }

  @override
  Future<void>? onPlay() {
    playing = true;
    return null;
  }

  @override
  bool isPlaying() => playing;
}

/// A line every 2 seconds from 1 second in, each 1.5 seconds long.
final _lines = [
  for (var i = 0; i < 60; i++)
    SubtitleLine(
      from: Duration(seconds: i * 2 + 1),
      to: Duration(milliseconds: i * 2000 + 2500),
      content: 'line $i',
    ),
];

Future<_Audio> _pumpList(WidgetTester tester, {int line = -1}) async {
  final audio = _Audio();
  audio.subtitleLines.value = Success(_lines);
  audio.updateSubtitlePosition(
    line == -1 ? .zero : _lines[line].from,
  );
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: 600,
            child: AudioSubtitleList(controller: audio),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return audio;
}

TextStyle _styleOf(WidgetTester tester, String text) => tester
    .widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    )
    .style;

/// How far the line is from the middle of the list.
double _offCenter(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text)).dy -
    tester.getCenter(find.byType(AudioSubtitleList)).dy;

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

  testWidgets('the current line is bold, the others faded', (tester) async {
    final audio = await _pumpList(tester, line: 3);
    expect(audio.subtitleLine.value, 3);
    final current = _styleOf(tester, 'line 3');
    final other = _styleOf(tester, 'line 4');
    expect(current.fontWeight, FontWeight.bold);
    expect(other.fontWeight, FontWeight.normal);
    expect(other.color!.a, lessThan(current.color!.a));
  });

  testWidgets('the current line follows the position, in the middle', (
    tester,
  ) async {
    final audio = await _pumpList(tester, line: 3);
    expect(_offCenter(tester, 'line 3').abs(), lessThan(1));

    // halfway through line 30, after a seek
    audio.updateSubtitlePosition(const Duration(milliseconds: 61700));
    await tester.pumpAndSettle();
    expect(audio.subtitleLine.value, 30);
    expect(_styleOf(tester, 'line 30').fontWeight, FontWeight.bold);
    expect(_offCenter(tester, 'line 30').abs(), lessThan(1));

    // in the pause after it
    audio.updateSubtitlePosition(const Duration(milliseconds: 62800));
    await tester.pumpAndSettle();
    expect(audio.subtitleLine.value, 30);
  });

  testWidgets('waits with the first line in the middle before it starts', (
    tester,
  ) async {
    final audio = await _pumpList(tester);
    expect(audio.subtitleLine.value, -1);
    expect(_offCenter(tester, 'line 0').abs(), lessThan(1));
    expect(_styleOf(tester, 'line 0').fontWeight, FontWeight.normal);
  });

  testWidgets('tapping a line plays from its start', (tester) async {
    final audio = await _pumpList(tester, line: 2);
    await tester.tap(find.text('line 6'));
    await tester.pumpAndSettle();
    expect(audio.seekedTo, _lines[6].from);
    expect(audio.playing, isTrue);
    expect(audio.subtitleLine.value, 6);
    expect(_offCenter(tester, 'line 6').abs(), lessThan(1));
  });

  testWidgets('scrolling by hand stops following for 3 seconds', (
    tester,
  ) async {
    final audio = await _pumpList(tester, line: 10);
    await tester.drag(find.text('line 10'), const Offset(0, 250));
    await tester.pump();
    final dragged = _offCenter(tester, 'line 10');
    expect(dragged, greaterThan(200));

    audio.updateSubtitlePosition(_lines[11].from);
    await tester.pump(const Duration(milliseconds: 300));
    expect(audio.subtitleLine.value, 11);
    expect(_styleOf(tester, 'line 11').fontWeight, FontWeight.bold);
    // still where the finger left it
    expect(_offCenter(tester, 'line 10'), dragged);

    await tester.pump(const Duration(milliseconds: 2600));
    expect(_offCenter(tester, 'line 10'), dragged);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_offCenter(tester, 'line 11').abs(), lessThan(1));
  });

  testWidgets('another drag before the 3 seconds are up waits again', (
    tester,
  ) async {
    await _pumpList(tester, line: 10);
    await tester.drag(find.text('line 10'), const Offset(0, 200));
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(find.text('line 10'), const Offset(0, -100));
    await tester.pump();
    final dragged = _offCenter(tester, 'line 10');

    await tester.pump(const Duration(milliseconds: 2900));
    expect(_offCenter(tester, 'line 10'), dragged);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_offCenter(tester, 'line 10').abs(), lessThan(1));
  });

  testWidgets('a finger on the list stops the scrolling to a line', (
    tester,
  ) async {
    final audio = await _pumpList(tester, line: 10);
    audio.updateSubtitlePosition(_lines[20].from);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AudioSubtitleList)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final touched = tester.getCenter(find.text('line 20')).dy;

    // the rest of the scrolling, which would have centred line 20
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(find.text('line 20')).dy, touched);

    // the drag moves the list as far as the finger
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    final dragged = tester.getCenter(find.text('line 20')).dy;
    expect(dragged - touched, greaterThan(50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(find.text('line 20')).dy, dragged);
  });

  testWidgets('a touch that ends without a scroll goes on to the line', (
    tester,
  ) async {
    final audio = await _pumpList(tester, line: 10);
    audio.updateSubtitlePosition(_lines[14].from);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AudioSubtitleList)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // taken by the system, say, so it is not a tap either
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(audio.seekedTo, isNull);
    expect(_offCenter(tester, 'line 14').abs(), lessThan(1));
  });
}
