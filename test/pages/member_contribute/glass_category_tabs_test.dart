import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/pages/member_contribute/widgets/glass_category_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _labels = ['视频', '图文', '合集', '音频'];

/// A category's list, as the 视频 one once its videos show: a sort row that
/// floats back in when scrolled toward the top, then the items.
class _List extends StatelessWidget {
  const _List(this.controller);

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        const FloatingUnderOverlay(
          header: SliverFloatingHeaderWidget(
            backgroundColor: Colors.white,
            child: SizedBox(key: ValueKey('sort'), height: 40),
          ),
        ),
        SliverList.builder(
          itemCount: 40,
          itemBuilder: (context, index) =>
              SizedBox(key: ValueKey('item$index'), height: 80),
        ),
      ],
    );
  }
}

void _size(WidgetTester tester, {double width = 412}) {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<(TabController, ScrollController)> _pump(
  WidgetTester tester, {
  double width = 412,
}) async {
  _size(tester, width: width);
  final tabs = TabController(length: _labels.length, vsync: tester);
  addTearDown(tabs.dispose);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GlassCategoryTabs(
          controller: tabs,
          labels: _labels,
          child: TabBarView(
            controller: tabs,
            children: [
              _List(scroll),
              for (final label in _labels.skip(1)) Center(child: Text(label)),
            ],
          ),
        ),
      ),
    ),
  );
  return (tabs, scroll);
}

double _top(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key))).dy;

void main() {
  testWidgets('the pill stands centered, 6 below the top, 40 tall', (
    tester,
  ) async {
    await _pump(tester);
    final pill = tester.getRect(find.byType(LiquidGlassTabBar));
    expect(pill.center.dx, closeTo(412 / 2, 0.01));
    expect(pill.width, lessThan(412 - 28));
    expect(pill.top, 6);
    expect(pill.height, 40);
  });

  testWidgets('categories wider than the row fill it 14 in and scroll', (
    tester,
  ) async {
    await _pump(tester, width: 200);
    final pill = tester.getRect(find.byType(LiquidGlassTabBar));
    expect(pill.left, 14);
    expect(pill.right, 200 - 14);
  });

  testWidgets('the list starts below the pill and scrolls under it', (
    tester,
  ) async {
    final (_, scroll) = await _pump(tester);
    expect(_top(tester, 'sort'), GlassCategoryTabs.extent);
    expect(_top(tester, 'item0'), GlassCategoryTabs.extent + 40);

    scroll.jumpTo(60);
    await tester.pump();
    // The first item now lies under the pill, drawn there for the glass.
    expect(_top(tester, 'item0'), GlassCategoryTabs.extent + 40 - 60);
    expect(find.byKey(const ValueKey('item0')), findsOneWidget);
  });

  testWidgets('the sort row floats back in below the pill', (
    tester,
  ) async {
    final (_, scroll) = await _pump(tester);
    scroll.jumpTo(800);
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(200, 500));
    // Back toward the top by more than the row with its room above it.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_top(tester, 'sort'), GlassCategoryTabs.extent);
  });

  testWidgets('without a header over it the sort row stands at the top', (
    tester,
  ) async {
    _size(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _List(scroll))));
    expect(_top(tester, 'sort'), 0);
    expect(_top(tester, 'item0'), 40);
  });

  testWidgets('a tap on a category switches to it', (tester) async {
    final (tabs, _) = await _pump(tester);
    await tester.tap(find.text('合集').first);
    await tester.pumpAndSettle();
    expect(tabs.index, 2);
  });
}
