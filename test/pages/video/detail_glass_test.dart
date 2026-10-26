import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/pages/video/widgets/detail_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('GlassDetailTabRow', () {
    late TabController controller;

    setUp(
      () => controller = TabController(length: 2, vsync: const TestVSync()),
    );
    tearDown(() => controller.dispose());

    Widget row({
      List<String> tabs = const ['简介', '评论'],
      RxInt? replyCount,
      RxBool? showDanmaku,
      VoidCallback? onSendDanmaku,
      VoidCallback? onToggleDanmaku,
      bool showPlatter = true,
      bool compact = false,
    }) => GlassDetailTabRow(
      compact: compact,
      controller: controller,
      tabs: tabs,
      replyCount: replyCount,
      showPlatter: showPlatter,
      onSendDanmaku: onSendDanmaku ?? () {},
      showDanmaku: showDanmaku ?? true.obs,
      onToggleDanmaku: onToggleDanmaku ?? () {},
    );

    testWidgets('stands 50 tall', (tester) async {
      await tester.pumpWidget(_app(row()));
      expect(tester.getSize(find.byType(GlassDetailTabRow)).height, 50);
      expect(GlassDetailTabRow.extent, 50);
    });

    testWidgets('shows the comment count as it changes', (tester) async {
      final count = (-1).obs;
      await tester.pumpWidget(_app(row(replyCount: count)));
      expect(find.text('评论'), findsOneWidget);

      count.value = 116;
      await tester.pump();
      expect(find.text('评论 116'), findsOneWidget);
      expect(find.text('简介'), findsOneWidget);
    });

    testWidgets('sends danmaku and toggles them', (tester) async {
      var sent = 0;
      var toggled = 0;
      final showDanmaku = true.obs;
      await tester.pumpWidget(
        _app(
          row(
            showDanmaku: showDanmaku,
            onSendDanmaku: () => sent++,
            onToggleDanmaku: () {
              toggled++;
              showDanmaku.value = !showDanmaku.value;
            },
          ),
        ),
      );
      final colorScheme = ColorScheme.of(
        tester.element(find.byType(GlassDetailTabRow)),
      );

      await tester.tap(find.text('发弹幕'));
      expect(sent, 1);

      expect(
        tester.widget<Icon>(find.byIcon(CustomIcons.dm_on)).color,
        colorScheme.primary,
      );
      await tester.tap(find.byIcon(CustomIcons.dm_on));
      await tester.pump();
      expect(toggled, 1);
      expect(
        tester.widget<Icon>(find.byIcon(CustomIcons.dm_off)).color,
        colorScheme.onSurfaceVariant,
      );
    });

    testWidgets('shows only the icon to send danmaku when narrow', (
      tester,
    ) async {
      expect(GlassDetailTabRow.isCompact(280, 2), isTrue);
      expect(GlassDetailTabRow.isCompact(412, 2), isFalse);
      expect(GlassDetailTabRow.isCompact(412, 3), isFalse);
      await tester.pumpWidget(_app(row(compact: true), width: 252));
      expect(find.text('发弹幕'), findsNothing);
      expect(find.byIcon(Icons.comment_outlined), findsOneWidget);
      expect(find.byTooltip('发弹幕'), findsOneWidget);
    });

    testWidgets('a single tab stands on no platter', (tester) async {
      controller.dispose();
      controller = TabController(length: 1, vsync: const TestVSync());
      await tester.pumpWidget(_app(row(tabs: ['评论'], showPlatter: false)));
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.indicator, isA<BoxDecoration>());
    });

    testWidgets('with no tabs keeps the danmaku buttons at the end', (
      tester,
    ) async {
      controller.dispose();
      controller = TabController(length: 0, vsync: const TestVSync());
      await tester.pumpWidget(_app(row(tabs: [])));
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('发弹幕'), findsOneWidget);
      expect(
        tester.getTopRight(find.byIcon(CustomIcons.dm_on)).dx,
        lessThan(400),
      );
    });
  });

  group('GlassTabsOverlay', () {
    Widget list(Key key) => Builder(
      builder: (context) => CustomScrollView(
        slivers: [
          HeaderOverlayInset.sliver(context),
          SliverToBoxAdapter(child: SizedBox(key: key, height: 100)),
        ],
      ),
    );

    testWidgets('lists start below the tabs, and panels beside at 0', (
      tester,
    ) async {
      final controller = TabController(length: 2, vsync: const TestVSync());
      addTearDown(controller.dispose);
      const under = Key('under');
      const beside = Key('beside');
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 600,
            child: Row(
              children: [
                Expanded(child: list(beside)),
                Expanded(
                  child: GlassTabsOverlay(
                    tabBar: GlassDetailTabRow(
                      controller: controller,
                      tabs: const ['简介', '评论'],
                      onSendDanmaku: () {},
                      showDanmaku: true.obs,
                      onToggleDanmaku: () {},
                    ),
                    pages: TabBarView(
                      controller: controller,
                      children: [list(under), const SizedBox()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          width: 800,
        ),
      );
      expect(tester.getTopLeft(find.byKey(under)).dy, 50);
      expect(tester.getTopLeft(find.byKey(beside)).dy, 0);
    });

    testWidgets('touches between the pills reach the list', (tester) async {
      final controller = TabController(length: 1, vsync: const TestVSync());
      addTearDown(controller.dispose);
      var tapped = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 600,
            child: GlassTabsOverlay(
              tabBar: GlassDetailTabRow(
                controller: controller,
                tabs: const ['简介'],
                onSendDanmaku: () {},
                showDanmaku: true.obs,
                onToggleDanmaku: () {},
              ),
              pages: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tapped++,
              ),
            ),
          ),
        ),
      );
      final pillEnd = tester.getTopRight(find.byType(TabBar)).dx;
      final sendStart = tester.getTopLeft(find.text('发弹幕')).dx;
      expect(sendStart - pillEnd, greaterThan(40));
      // Beside the tab pill, above it, and in the fade below the row.
      await tester.tapAt(Offset((pillEnd + sendStart) / 2, 26));
      await tester.tapAt(const Offset(200, 3));
      await tester.tapAt(const Offset(200, 56));
      expect(tapped, 3);
    });

    testWidgets('takes a new controller as the tabs grow', (tester) async {
      await tester.pumpWidget(
        _app(const SizedBox(height: 600, child: _Tabs())),
      );
      expect(find.text('评论'), findsOneWidget);
      expect(find.text('播放列表'), findsNothing);

      tester.state<_TabsState>(find.byType(_Tabs)).grow();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('播放列表'), findsOneWidget);

      await tester.tap(find.text('播放列表'));
      await tester.pumpAndSettle();
      expect(find.text('page 2'), findsOneWidget);
    });

    // As the window turns, the old tab bar rebuilds for the new MediaQuery
    // in the same frame as its controller is replaced.
    testWidgets('takes a new controller as the tabs grow while turning', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(const SizedBox(height: 600, child: _Tabs())),
      );
      tester.state<_TabsState>(find.byType(_Tabs)).grow();
      tester.view.physicalSize = const Size(2400, 1080);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('播放列表'), findsOneWidget);
    });
  });

  testWidgets('GlassReplySortRow sorts on a tap', (tester) async {
    var sorted = 0;
    await tester.pumpWidget(
      _app(
        GlassReplySortRow(
          desc: '最热评论',
          label: '最热',
          onSort: () => sorted++,
        ),
      ),
    );
    expect(find.text('最热评论'), findsOneWidget);
    await tester.tap(find.text('最热'));
    expect(sorted, 1);
  });

  testWidgets('GlassReplyFab replies on a tap', (tester) async {
    var replied = 0;
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: GlassReplyFab(onTap: () => replied++),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(GlassReplyFab)),
      const Size.square(GlassReplyFab.size),
    );
    await tester.tap(find.byTooltip('发表评论'));
    expect(replied, 1);
  });
}

/// Replaces its controller while building the tab row, as the video page's
/// buildTabBar does, before building the pages that take it.
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with TickerProviderStateMixin {
  var tabs = ['简介', '评论'];
  late var controller = TabController(length: tabs.length, vsync: this);

  void grow() => setState(() => tabs = [...tabs, '播放列表']);

  Widget buildTabBar() {
    if (controller.length != tabs.length) {
      controller.dispose();
      controller = TabController(
        vsync: this,
        length: tabs.length,
        initialIndex: controller.index.clamp(0, tabs.length - 1),
      );
    }
    return GlassDetailTabRow(
      controller: controller,
      tabs: tabs,
      onSendDanmaku: () {},
      showDanmaku: true.obs,
      onToggleDanmaku: () {},
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = buildTabBar();
    return GlassTabsOverlay(
      tabBar: tabBar,
      pages: TabBarView(
        controller: controller,
        children: [
          for (var i = 0; i < tabs.length; i++) Center(child: Text('page $i')),
        ],
      ),
    );
  }
}
