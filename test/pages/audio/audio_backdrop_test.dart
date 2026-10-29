import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/pages/audio/backdrop/audio_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A PNG of [color], as a cover.
Future<Uint8List> _png(WidgetTester tester, Color color) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    final image = await recorder.endRecording().toImage(16, 9);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

AudioBackdropState _state(WidgetTester tester) =>
    tester.state<AudioBackdropState>(find.byType(AudioBackdrop));

/// Lets the cover decode, which needs real time.
Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Widget _app({ImageProvider? image, bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: AudioBackdrop(image: image, placeholder: Colors.black),
    ),
  ),
);

void main() {
  tearDown(() => AudioBackdrop.debugFps.value = null);

  testWidgets('moves while it shows', (tester) async {
    await tester.pumpWidget(_app());
    expect(_state(tester).isRunning, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_state(tester).time, closeTo(2, 0.1));
  });

  testWidgets('stops under a page and goes on from where it was', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final state = _state(tester);
    final before = state.time;

    final navigator = tester.state<NavigatorState>(find.byType(Navigator))
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('上面')),
        ),
      );
    await tester.pumpAndSettle();
    expect(state.isRunning, isFalse);
    final covered = state.time;
    final renders = state.renders;
    await tester.pump(const Duration(seconds: 10));
    expect(state.time, covered);
    expect(state.renders, renders);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.isRunning, isTrue);
    // From where it stopped: the ten seconds under the page don't count.
    expect(state.time, lessThan(covered + 1));
    expect(state.time, greaterThan(before));
  });

  testWidgets('stops while the app is away', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    final state = _state(tester);
    // As the platform goes, a step at a time.
    for (final step in const [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    expect(state.isRunning, isFalse);
    for (final step in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    await tester.pump();
    expect(state.isRunning, isTrue);
  });

  testWidgets('Reduce Motion runs it ten times slower', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(_state(tester).time, closeTo(0.3, 0.02));
  });

  testWidgets('a new cover fades in over half a second', (tester) async {
    final first = MemoryImage(await _png(tester, Colors.red));
    await tester.pumpWidget(_app(image: first));
    await _load(tester);
    final state = _state(tester);
    // The first one faded in from the placeholder.
    await tester.pump(const Duration(seconds: 1));
    expect(state.dissolve, 1);

    final second = MemoryImage(await _png(tester, Colors.blue));
    await tester.pumpWidget(_app(image: second));
    await _load(tester);
    final start = state.dissolve;
    expect(start, lessThan(0.5));
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.dissolve, closeTo(start + 0.5, 0.15));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.dissolve, 1);
  });

  testWidgets('a cover already in the cache shows too', (tester) async {
    final cover = MemoryImage(await _png(tester, Colors.red));
    await tester.pumpWidget(_app(image: cover));
    await _load(tester);
    expect(_state(tester).hasCover, isTrue);

    // A new backdrop, as the page opens again: the cache answers from
    // inside addListener.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(image: cover));
    await _load(tester);
    expect(_state(tester).hasCover, isTrue);
  });

  testWidgets('a cover that fails fades to the placeholder', (tester) async {
    await tester.pumpWidget(
      _app(image: MemoryImage(await _png(tester, Colors.red))),
    );
    await _load(tester);
    final state = _state(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(state.hasCover, isTrue);

    await tester.pumpWidget(
      _app(image: MemoryImage(Uint8List.fromList([1, 2, 3]))),
    );
    await _load(tester);
    expect(state.hasCover, isFalse);
    expect(state.dissolve, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.dissolve, 1);
  });

  testWidgets('no cover fades to the placeholder', (tester) async {
    await tester.pumpWidget(
      _app(image: MemoryImage(await _png(tester, Colors.red))),
    );
    await _load(tester);
    final state = _state(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(state.hasCover, isTrue);

    await tester.pumpWidget(_app());
    await tester.pump();
    expect(state.hasCover, isFalse);
    expect(state.dissolve, lessThan(1));
  });

  testWidgets('at 0 a second it holds still, but fades a cover in', (
    tester,
  ) async {
    AudioBackdrop.debugFps.value = 0;
    await tester.pumpWidget(_app());
    final state = _state(tester);
    expect(state.isRunning, isFalse);

    await tester.pumpWidget(
      _app(image: MemoryImage(await _png(tester, Colors.green))),
    );
    await _load(tester);
    expect(state.isRunning, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(state.dissolve, 1);
    expect(state.isRunning, isFalse);
    expect(state.time, 0);
  });
}
