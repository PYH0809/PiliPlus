import 'package:PiliPlus/common/widgets/custom_icon.dart';
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
