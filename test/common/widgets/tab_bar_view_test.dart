import 'dart:io';

import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart'
    show SlideDragGestureRecognizer;
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// A tab's page: a list, as the tabs' pages are, which takes vertical drags.
Widget _page(String name) => ListView.builder(
  key: ValueKey(name),
  itemCount: 30,
  itemBuilder: (context, index) => SizedBox(height: 80, child: Text(name)),
);

/// Tabs of 动态详情 sort: 转发, 评论 and 赞, the first of which has tabs of its
/// own, as 追番 has 想看, 在看 and 看过.
Future<(TabController outer, TabController inner)> _pump(
  WidgetTester tester, {
  int initialOuter = 0,
  int initialInner = 0,
}) async {
  tester.view
    ..physicalSize = const Size(412, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final outer = TabController(
    length: 3,
    initialIndex: initialOuter,
    vsync: tester,
  );
  addTearDown(outer.dispose);
  final inner = TabController(
    length: 3,
    initialIndex: initialInner,
    vsync: tester,
  );
  addTearDown(inner.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: tabBarView(
          controller: outer,
          children: [
            tabBarView(
              controller: inner,
              children: [_page('想看'), _page('在看'), _page('看过')],
            ),
            _page('评论'),
            _page('赞'),
          ],
        ),
      ),
    ),
  );
  return (outer, inner);
}

/// A swipe across the middle of the screen: to the next tab if [forward].
Future<void> _swipe(WidgetTester tester, {required bool forward}) async {
  await tester.flingFrom(
    const Offset(206, 400),
    Offset(forward ? -240 : 240, 0),
    1500,
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-tab-bar-view-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('a swipe turns the inner tabs while they have more', (
    tester,
  ) async {
    final (outer, inner) = await _pump(tester);

    await _swipe(tester, forward: true);
    expect((outer.index, inner.index), (0, 1));
    await _swipe(tester, forward: true);
    expect((outer.index, inner.index), (0, 2));

    await _swipe(tester, forward: false);
    expect((outer.index, inner.index), (0, 1));
  });

  testWidgets('a swipe past the last inner tab turns the outer tab', (
    tester,
  ) async {
    final (outer, inner) = await _pump(tester, initialInner: 2);

    await _swipe(tester, forward: true);
    expect((outer.index, inner.index), (1, 2));
    expect(find.byKey(const ValueKey('评论')), findsOneWidget);
  });

  testWidgets('a swipe back past the first inner tab turns the outer tab', (
    tester,
  ) async {
    // The inner tabs sit on the outer's second tab here.
    tester.view
      ..physicalSize = const Size(412, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outer = TabController(length: 3, initialIndex: 1, vsync: tester);
    addTearDown(outer.dispose);
    final inner = TabController(length: 2, vsync: tester);
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: tabBarView(
            controller: outer,
            children: [
              _page('转发'),
              tabBarView(
                controller: inner,
                children: [_page('未发布'), _page('已发布')],
              ),
              _page('赞'),
            ],
          ),
        ),
      ),
    );

    await _swipe(tester, forward: false);
    expect((outer.index, inner.index), (0, 0));
    expect(find.byKey(const ValueKey('转发')), findsOneWidget);
  });

  testWidgets('the outer tabs bring their inner ones back where they were', (
    tester,
  ) async {
    final (outer, inner) = await _pump(tester, initialInner: 2);

    await _swipe(tester, forward: true);
    expect((outer.index, inner.index), (1, 2));

    // Back onto the inner tabs, then on through them.
    await _swipe(tester, forward: false);
    expect((outer.index, inner.index), (0, 2));
    await _swipe(tester, forward: false);
    expect((outer.index, inner.index), (0, 1));
  });

  testWidgets('a swipe on tabs of one level still turns them', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tabs = TabController(length: 3, initialIndex: 1, vsync: tester);
    addTearDown(tabs.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: tabBarView(
            controller: tabs,
            children: [_page('转发'), _page('评论'), _page('赞')],
          ),
        ),
      ),
    );

    await _swipe(tester, forward: true);
    expect(tabs.index, 2);
    // Nothing past the last: the swipe goes nowhere.
    await _swipe(tester, forward: true);
    expect(tabs.index, 2);
    await _swipe(tester, forward: false);
    await _swipe(tester, forward: false);
    expect(tabs.index, 0);
  });

  testWidgets('a drag mostly up and down scrolls the list, not the tabs', (
    tester,
  ) async {
    final (outer, inner) = await _pump(tester, initialInner: 2);

    await tester.dragFrom(const Offset(206, 600), const Offset(-60, -300));
    await tester.pumpAndSettle();
    expect((outer.index, inner.index), (0, 2));
  });

  group('on a panel that closes on a swipe from its edges', () {
    // As 番剧详情 → 点评: 长评 and 短评 on a panel that, with 侧滑关闭 on,
    // closes on a swipe from within 30 of either edge.
    Future<(TabController, ValueNotifier<bool>)> pumpPanel(
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(412, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tabs = TabController(length: 2, initialIndex: 1, vsync: tester);
      addTearDown(tabs.dispose);
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      bool inside(double dx) => dx > 30 && dx < 412 - 30;
      final slide = SlideDragGestureRecognizer(isDxAllowed: (dx) => !inside(dx))
        ..onStart = ((_) => closing.value = true);
      addTearDown(slide.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Listener(
              onPointerDown: slide.addPointer,
              child: tabBarView(
                controller: tabs,
                isDxAllowed: inside,
                children: [_page('长评'), _page('短评')],
              ),
            ),
          ),
        ),
      );
      return (tabs, closing);
    }

    testWidgets('a swipe from the edge closes it, not turns the tabs', (
      tester,
    ) async {
      final (tabs, closing) = await pumpPanel(tester);

      // A quick swipe: its first move is past both slops at once, where the
      // tabs, the deeper of the two, would take it.
      final gesture = await tester.startGesture(const Offset(10, 400));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(closing.value, isTrue);
      expect(tabs.index, 1);
    });

    testWidgets('a swipe across the middle still turns the tabs', (
      tester,
    ) async {
      final (tabs, closing) = await pumpPanel(tester);

      await _swipe(tester, forward: false);
      expect(closing.value, isFalse);
      expect(tabs.index, 0);
    });
  });

  testWidgets('DefaultTabController tabs hand off as well', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outer = TabController(length: 2, vsync: tester);
    addTearDown(outer.dispose);
    late TabController inner;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: tabBarView(
            controller: outer,
            children: [
              DefaultTabController(
                length: 2,
                initialIndex: 1,
                child: Builder(
                  builder: (context) {
                    inner = DefaultTabController.of(context);
                    return tabBarView(
                      children: [_page('想看'), _page('看过')],
                    );
                  },
                ),
              ),
              _page('评论'),
            ],
          ),
        ),
      ),
    );

    await _swipe(tester, forward: true);
    expect((outer.index, inner.index), (1, 1));
  });
}
