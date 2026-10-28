import 'dart:io';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/pages/dynamics/widgets/glass_header.dart';
import 'package:PiliPlus/pages/mine/widgets/glass_header.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// The page's list, as the mine page lays it out: starting below the header,
/// with room at the end for the navigation bar.
class _List extends StatelessWidget {
  const _List({this.onTap});

  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return refreshIndicator(
      onRefresh: () => Future.delayed(const Duration(seconds: 1)),
      child: ListView(
        padding: .only(top: HeaderOverlayInset.of(context), bottom: 150),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 20; i++)
            GestureDetector(
              behavior: .opaque,
              onTap: () => onTap?.call(i),
              child: SizedBox(key: ValueKey('item$i'), height: 80),
            ),
        ],
      ),
    );
  }
}

List<Widget> _actions(int count) => [
  for (var i = 0; i < count; i++) ...[
    if (i > 0) const SizedBox(width: 8),
    GlassCircle(icon: Icons.settings_outlined, tooltip: 'a$i', onTap: () {}),
  ],
];

Future<void> _pump(
  WidgetTester tester, {
  int actions = 4,
  bool showBackBtn = false,
  double width = 412,
  ValueChanged<int>? onTap,
}) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MineGlassBody(
          showBackBtn: showBackBtn,
          actions: _actions(actions),
          content: _List(onTap: onTap),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  // The refresh indicator reads its displacement from the settings.
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-mine-header-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('the buttons are 40 dp circles 8 apart, the last 14 in', (
    tester,
  ) async {
    await _pump(tester);
    final circles = find.byType(GlassCircle);
    expect(circles, findsNWidgets(4));
    final rects = [for (var i = 0; i < 4; i++) tester.getRect(circles.at(i))];
    for (final rect in rects) {
      expect(rect.size, const Size(40, 40));
      expect(rect.top, 6);
    }
    for (var i = 1; i < 4; i++) {
      expect(rects[i].left - rects[i - 1].right, 8);
    }
    expect(rects.last.right, 412 - 14);
  });

  testWidgets('the list starts below the header and scrolls under it', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('item0'))).dy, 50);
    await tester.drag(find.byType(ListView), const Offset(0, -30));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('item0'))).dy,
      lessThan(50),
    );
    // Still under the header's buttons, which stay put.
    expect(tester.getRect(find.byType(GlassCircle).first).top, 6);
  });

  testWidgets('a refresh comes out from under the header', (tester) async {
    await _pump(tester);
    expect(HeaderOverlayInset.of(tester.element(find.byType(ListView))), 50);
    final gesture = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    final indicator = find.byType(RefreshProgressIndicator);
    expect(indicator, findsOneWidget);
    expect(tester.getRect(indicator).top, greaterThanOrEqualTo(50));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the last item clears a bar along the bottom', (tester) async {
    await _pump(tester);
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('item19'))).dy,
      800 - 150,
    );
  });

  testWidgets('touches between the buttons and on the fade reach the list', (
    tester,
  ) async {
    int? tapped;
    await _pump(tester, onTap: (i) => tapped = i);
    // Left of the buttons, and in the fade below them.
    await tester.tapAt(const Offset(60, 60));
    expect(tapped, 0);
  });

  testWidgets('in the tab, no back button', (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Back'), findsNothing);
    expect(
      tester.getRect(find.byType(GlassCircle).first).left,
      greaterThan(14),
    );
  });

  testWidgets('opened as a page, a glass back button 14 in pops it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Material(
          child: MineGlassBody(
            showBackBtn: true,
            actions: _actions(5),
            content: const _List(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    final rect = tester.getRect(
      find.ancestor(of: back, matching: find.byType(GlassCircle)),
    );
    expect(rect, const Rect.fromLTWH(14, 6, 40, 40));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(MineGlassBody), findsNothing);
  });

  testWidgets('a narrow window shrinks the buttons to fit', (tester) async {
    await _pump(tester, actions: 7, showBackBtn: true, width: 320);
    expect(tester.takeException(), isNull);
    final circles = find.byType(GlassCircle);
    expect(circles, findsNWidgets(8));
    for (var i = 0; i < 8; i++) {
      final rect = tester.getRect(circles.at(i));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
  });
}
