import 'package:PiliPlus/pages/search_panel/floating_header_below.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _inset = 96.0;
const _row = 36.0;

final _filters = find.byKey(const ValueKey('filters'));
final _first = find.byKey(const ValueKey('item0'));

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(412, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverFloatingHeaderBelow(
              inset: _inset,
              backgroundColor: Colors.white,
              child: SizedBox(key: ValueKey('filters'), height: _row),
            ),
            SliverList.builder(
              itemCount: 60,
              itemBuilder: (context, index) =>
                  SizedBox(key: ValueKey('item$index'), height: 80),
            ),
          ],
        ),
      ),
    ),
  );
}

// A wheel, which scrolls by exactly [by], with no touch slop, which way it
// went kept as a drag's would be.
Future<void> _scroll(WidgetTester tester, double by) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  final center = tester.getCenter(find.byType(CustomScrollView));
  await tester.sendEventToBinding(pointer.hover(center));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, by)));
  await tester.pump();
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets('at rest the row stands below the header, then the results', (
    tester,
  ) async {
    await _pump(tester);
    expect(_top(tester, _filters), _inset);
    expect(_top(tester, _first), _inset + _row);
  });

  testWidgets('the row scrolls away under the header with the results', (
    tester,
  ) async {
    await _pump(tester);
    await _scroll(tester, 20);
    expect(_top(tester, _filters), _inset - 20);
    expect(_top(tester, _first), _inset + _row - 20);
  });

  testWidgets('scrolled back by its own height, the row stands below the '
      'header again', (tester) async {
    await _pump(tester);
    await _scroll(tester, 600);
    expect(find.byKey(const ValueKey('filters')).hitTestable(), findsNothing);
    await _scroll(tester, -_row / 2);
    // Halfway out from under the header.
    expect(_top(tester, _filters), _inset - _row / 2);
    await _scroll(tester, -_row / 2);
    expect(_top(tester, _filters), _inset);
    // It stays there as the results scroll back under it.
    await _scroll(tester, -100);
    expect(_top(tester, _filters), _inset);
  });

  testWidgets('it hides again as the results scroll on', (tester) async {
    await _pump(tester);
    await _scroll(tester, 600);
    await _scroll(tester, -_row);
    await _scroll(tester, 10);
    expect(_top(tester, _filters), _inset - 10);
  });

  testWidgets('back at the top it is where it was at rest', (tester) async {
    await _pump(tester);
    await _scroll(tester, 600);
    await _scroll(tester, -_row);
    await _scroll(tester, -700);
    expect(_top(tester, _filters), _inset);
    expect(_top(tester, _first), _inset + _row);
  });
}
