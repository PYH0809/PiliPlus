import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/pages/audio/widgets/glass_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _bar = ValueKey('bar');

/// The controls [width] wide at [textScale], with times of over an hour and
/// a desktop's volume button after them.
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
}) async {
  final playPause = AnimationController(vsync: const TestVSync());
  addTearDown(playPause.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: .bottomCenter,
            child: SizedBox(
              width: width,
              child: AudioGlassControls(
                position: const Text('1:02:03'),
                progress: const SizedBox(
                  key: _bar,
                  width: double.infinity,
                  height: 12,
                ),
                duration: const Text('1:45:00'),
                trailing: const SizedBox.square(dimension: 44),
                playModeIcon: const Icon(Icons.repeat),
                onPlayMode: () {},
                onPrevious: () {},
                playPause: playPause,
                onPlayPause: () {},
                onNext: () {},
                onPlaylist: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The progress' capsule, the pane under the position.
Rect _capsule(WidgetTester tester) {
  final center = tester.getCenter(find.text('1:02:03'));
  return tester
      .widgetList(find.byType(LiquidGlass))
      .map((pane) => tester.getRect(find.byWidget(pane)))
      .firstWhere((rect) => rect.contains(center));
}

void main() {
  testWidgets('the times stand at their size beside a wide bar', (
    tester,
  ) async {
    await _pump(tester, width: 380);

    final capsule = _capsule(tester);
    final position = tester.getRect(find.text('1:02:03'));
    final duration = tester.getRect(find.text('1:45:00'));
    final bar = tester.getRect(find.byKey(_bar));
    // Drawn at the size the text stands at.
    expect(
      position.width,
      tester.renderObject<RenderBox>(find.text('1:02:03')).size.width,
    );
    expect(position.left, capsule.left + 18);
    expect(bar.left, position.right + 12);
    expect(duration.left, bar.right + 12);
    // The bar takes what the times, the gaps and the volume leave.
    expect(
      bar.width,
      capsule.width - 18 - 4 - 44 - 2 * 12 - position.width - duration.width,
    );
    expect(bar.width, greaterThan(AudioGlassControls.minProgressWidth));
    // Each centered on the capsule's height.
    for (final rect in [position, bar, duration]) {
      expect(rect.center.dy, closeTo(capsule.center.dy, 0.5));
    }
  });

  testWidgets('in a narrow window at a large text size the times shrink, '
      'not the bar', (tester) async {
    await _pump(tester, width: 220, textScale: 2);

    expect(tester.takeException(), isNull);
    final capsule = _capsule(tester);
    final position = tester.getRect(find.text('1:02:03'));
    final duration = tester.getRect(find.text('1:45:00'));
    final bar = tester.getRect(find.byKey(_bar));
    expect(
      bar.width,
      greaterThanOrEqualTo(AudioGlassControls.minProgressWidth),
    );
    expect(position.left, greaterThanOrEqualTo(capsule.left));
    expect(duration.right, lessThanOrEqualTo(capsule.right));
    expect(bar.left, greaterThanOrEqualTo(position.right));
    expect(duration.left, greaterThanOrEqualTo(bar.right));
    // The text is drawn smaller than it would stand.
    expect(
      position.width,
      lessThan(tester.renderObject<RenderBox>(find.text('1:02:03')).size.width),
    );
  });

  testWidgets('a large text size keeps to the capsule\'s height', (
    tester,
  ) async {
    await _pump(tester, width: 380, textScale: 3);

    expect(tester.takeException(), isNull);
    final capsule = _capsule(tester);
    final position = tester.getRect(find.text('1:02:03'));
    expect(position.top, greaterThanOrEqualTo(capsule.top));
    expect(position.bottom, lessThanOrEqualTo(capsule.bottom));
  });
}
