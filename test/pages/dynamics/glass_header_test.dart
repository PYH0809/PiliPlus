import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/pages/dynamics/widgets/glass_header.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _labels = ['全部', '投稿', '番剧', '专栏', 'UP'];

/// A feed as each tab has: a list starting below the header.
class _Feed extends StatelessWidget {
  const _Feed();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        HeaderOverlayInset.sliver(context),
        SliverList.builder(
          itemCount: 40,
          itemBuilder: (context, index) =>
              SizedBox(key: ValueKey('feed$index'), height: 80),
        ),
      ],
    );
  }
}

/// The vertical panel of UPs, as `UpPanel` lays it out.
class _UpColumn extends StatelessWidget {
  const _UpColumn();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: CustomScrollView(
        slivers: [
          HeaderOverlayInset.sliver(context),
          SliverList.builder(
            itemCount: 20,
            itemBuilder: (context, index) =>
                SizedBox(key: ValueKey('up$index'), height: 60),
          ),
        ],
      ),
    );
  }
}

Future<TabController> _pump(
  WidgetTester tester, {
  Widget content = const _Feed(),
  bool below = false,
  Widget? leading,
  Widget? drawer,
  Widget? endDrawer,
  bool plusOnLeft = false,
  double width = 412,
}) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TabController(length: _labels.length, vsync: tester);
  addTearDown(controller.dispose);
  final plus = GlassCircle(icon: Icons.add, tooltip: '发布动态', onTap: () {});
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        drawer: drawer,
        endDrawer: endDrawer,
        body: DynamicsGlassBody(
          below: below,
          content: content,
          header: DynamicsGlassHeader(
            controller: controller,
            labels: _labels,
            leading: plusOnLeft ? plus : leading,
            trailing: plusOnLeft ? leading : plus,
            fade: below ? 0 : 16,
          ),
        ),
      ),
    ),
  );
  return controller;
}

Widget _drawerButton({bool end = false}) => Builder(
  builder: (context) => GlassCircle(
    icon: Icons.menu,
    tooltip: 'drawer',
    onTap: end
        ? Scaffold.of(context).openEndDrawer
        : Scaffold.of(context).openDrawer,
  ),
);

void main() {
  testWidgets('the pill sits 14 in, with a 40 dp plus at its end', (
    tester,
  ) async {
    await _pump(tester);
    final pill = tester.getRect(find.byType(LiquidGlassTabBar));
    expect(pill.left, 14);
    expect(pill.top, 6);
    expect(pill.height, 40);
    final plus = tester.getRect(find.byType(GlassCircle));
    expect(plus.size, const Size(40, 40));
    expect(plus.right, 412 - 14);
    expect(plus.left - pill.right, 8);
  });

  testWidgets('the feed starts below the header and scrolls under it', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy, 50);
    await tester.drag(find.byType(_Feed), const Offset(0, -30));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy,
      lessThan(50),
    );
  });

  testWidgets('a refresh comes out from under the header', (tester) async {
    await _pump(tester);
    // RefreshIndicator takes its edgeOffset from here.
    expect(HeaderOverlayInset.of(tester.element(find.byType(_Feed))), 50);
  });

  testWidgets('leftFixed: the panel and the feed both start below', (
    tester,
  ) async {
    await _pump(
      tester,
      content: const Row(
        children: [
          _UpColumn(),
          Expanded(child: _Feed()),
        ],
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('up0'))),
      const Offset(0, 50),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy, 50);
    // The header spans the whole width, over the panel too.
    expect(tester.getRect(find.byType(LiquidGlassTabBar)).left, 14);
  });

  testWidgets('rightFixed: the panel and the feed both start below', (
    tester,
  ) async {
    await _pump(
      tester,
      content: const Row(
        children: [
          Expanded(child: _Feed()),
          _UpColumn(),
        ],
      ),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('up0'))).dy, 50);
    expect(tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy, 50);
  });

  testWidgets('top: the bar of UPs and the feed lie below the header', (
    tester,
  ) async {
    await _pump(
      tester,
      below: true,
      content: const Column(
        children: [
          SizedBox(key: ValueKey('upBar'), height: 76),
          Expanded(child: _Feed()),
        ],
      ),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('upBar'))).dy, 50);
    expect(tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy, 126);
    expect(HeaderOverlayInset.of(tester.element(find.byType(_Feed))), 0);
  });

  testWidgets('leftDrawer: the drawer opens from a glass button, at 0', (
    tester,
  ) async {
    await _pump(
      tester,
      leading: _drawerButton(),
      drawer: const Drawer(child: _UpColumn()),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy, 50);
    await tester.tap(find.byTooltip('drawer'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('up0'))).dy, 0);
  });

  testWidgets('rightDrawer: the plus on the left, the drawer on the right', (
    tester,
  ) async {
    await _pump(
      tester,
      leading: _drawerButton(end: true),
      endDrawer: const Drawer(child: _UpColumn()),
      plusOnLeft: true,
    );
    expect(tester.getRect(find.byTooltip('发布动态')).left, 14);
    expect(tester.getRect(find.byTooltip('drawer')).right, 412 - 14);
    await tester.tap(find.byTooltip('drawer'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('up0'))).dy, 0);
  });

  testWidgets('logged out: no panel, and the feed still starts at 50', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(_UpColumn), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('feed0'))).dy, 50);
  });

  testWidgets('picking an UP moves the platter to UP, in view', (
    tester,
  ) async {
    final controller = await _pump(
      tester,
      width: 360,
      leading: _drawerButton(),
    );
    controller.index = 4;
    await tester.pumpAndSettle();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 4);
    final pill = tester.getRect(find.byType(LiquidGlassTabBar));
    final up = tester.getRect(find.text('UP'));
    expect(up.left, greaterThanOrEqualTo(pill.left));
    expect(up.right, lessThanOrEqualTo(pill.right));
  });

  testWidgets('the plus is labelled 发布动态 and answers Enter', (
    tester,
  ) async {
    var taps = 0;
    tester.view
      ..physicalSize = const Size(412, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassCircle(
            icon: Icons.add,
            tooltip: '发布动态',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('发布动态'), findsOneWidget);
    expect(find.byType(LiquidGlass), findsOneWidget);
    Focus.of(tester.element(find.byType(LiquidGlass))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });
}
