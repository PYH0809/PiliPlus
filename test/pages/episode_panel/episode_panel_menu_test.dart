import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/episode_panel/view.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

List<Part> _parts(int count) => [
  for (var i = 1; i <= count; i++)
    Part(cid: i, page: i, part: 'P$i 第$i集', duration: 60),
];

/// The 分P panel as the video page opens it in its sheet: titled, with a way
/// to close and to reverse the order it plays in.
EpisodePanel _panel({
  bool isReversed = false,
  VoidCallback? onReverse,
  int count = 30,
}) => EpisodePanel(
  enableSlide: false,
  type: EpisodeType.part,
  isSidePanel: false,
  introController: UgcIntroController()
    ..videoDetail.value = (VideoDetailData(
      aid: 1,
      bvid: 'BV1xx411c7mD',
      pages: _parts(count),
    )..isPageReversed = isReversed),
  onReverse: onReverse ?? () {},
);

/// Pumps [panel] on a route of its own over a home page, as the sheet is.
/// The panel closes itself with Get.back, so the app is a GetMaterialApp.
Future<void> _pump(WidgetTester tester, Widget panel) async {
  tester.view
    ..physicalSize = const Size(412, 915)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const GetMaterialApp(home: Scaffold(body: Text('home'))),
  );
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(MaterialPageRoute<void>(builder: (_) => panel));
  await tester.pumpAndSettle();
}

/// Where the bar's glass ends; the fade under it lies over the list.
double _barBottom(WidgetTester tester) =>
    tester.widget<GlassAppBar>(find.byType(GlassAppBar)).preferredSize.height;

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String row) async {
  await _openMenu(tester);
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

/// The check at the end of [row] in the open menu.
Finder _checkOf(String row) => find.descendant(
  of: find.ancestor(of: find.text(row), matching: find.byType(Row)).first,
  matching: find.byIcon(Icons.check),
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-episode-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('glass off', () {
    setUp(() => GlassAppBar.debugEnabled = false);
    tearDown(() => GlassAppBar.debugEnabled = null);

    testWidgets('the bar keeps the title, one menu button and close', (
      tester,
    ) async {
      await _pump(tester, _panel());

      expect(find.text('分P'), findsOneWidget);
      expect(find.byTooltip('更多'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);
      // The bare icons that acted at a tap are gone from the bar.
      for (final tooltip in ['跳至顶部', '跳至底部', '跳至当前', '倒序播放', '倒序']) {
        expect(find.byTooltip(tooltip), findsNothing, reason: tooltip);
      }
      expect(find.byType(GlassAppBar), findsNothing);
    });

    testWidgets('the menu says what each action does, in words', (
      tester,
    ) async {
      await _pump(tester, _panel());
      await _openMenu(tester);

      for (final row in ['跳到顶部', '跳到底部', '跳到当前播放', '倒序播放', '倒序显示']) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      // Words only, no icons, and nothing checked yet.
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('跳到底部 and 跳到顶部 scroll the list', (tester) async {
      await _pump(tester, _panel());
      // The list scrolls on the primary scroll controller, so read its own.
      ScrollPosition list() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

      await _pick(tester, '跳到底部');
      expect(list().pixels, greaterThan(1000));

      await _pick(tester, '跳到顶部');
      expect(list().pixels, 0);
    });

    testWidgets('倒序显示 turns the list over and shows a check after', (
      tester,
    ) async {
      await _pump(tester, _panel());
      CustomScrollView list() =>
          tester.widget<CustomScrollView>(find.byType(CustomScrollView));
      expect(list().reverse, isFalse);

      await _pick(tester, '倒序显示');
      expect(list().reverse, isTrue);

      await _openMenu(tester);
      expect(_checkOf('倒序显示'), findsOneWidget);
      expect(_checkOf('倒序播放'), findsNothing);
    });

    testWidgets('倒序播放 is checked while the order is reversed', (
      tester,
    ) async {
      await _pump(tester, _panel(isReversed: true));
      await _openMenu(tester);

      expect(_checkOf('倒序播放'), findsOneWidget);
    });

    testWidgets('倒序播放 acts once the menu has gone, so the sheet it closes '
        'first is the sheet, not the menu', (tester) async {
      var reversed = 0;
      await _pump(tester, _panel(onReverse: () => reversed++));

      await _pick(tester, '倒序播放');

      expect(reversed, 1);
      expect(find.byType(EpisodePanel), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('glass on', () {
    setUp(() => GlassAppBar.debugEnabled = true);
    tearDown(() => GlassAppBar.debugEnabled = null);

    testWidgets('the bar floats over the list, which starts below it', (
      tester,
    ) async {
      await _pump(tester, _panel());

      final bar = find.byType(GlassAppBar);
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.byTooltip('更多')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.byTooltip('关闭')),
        findsOneWidget,
      );
      // The list runs under the bar, from the top of the sheet...
      final list = tester.getRect(find.byType(CustomScrollView));
      expect(list.top, 0);
      // ...and its first row starts below it.
      expect(
        tester.getTopLeft(find.text('P1 第1集')).dy,
        greaterThanOrEqualTo(_barBottom(tester)),
      );
    });

    testWidgets('scrolled, the rows pass under the bar', (tester) async {
      await _pump(tester, _panel());
      await _pick(tester, '跳到底部');
      await _pick(tester, '跳到顶部');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      final barBottom = _barBottom(tester);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.startsWith('P') ?? false) &&
              tester.getTopLeft(find.byWidget(w)).dy < barBottom,
        ),
        findsWidgets,
      );
    });

    testWidgets('跳到当前播放 leaves the current row below the bar', (tester) async {
      await _pump(tester, _panel());
      await _pick(tester, '跳到底部');
      await _pick(tester, '跳到当前播放');

      expect(
        tester.getTopLeft(find.text('P1 第1集')).dy,
        greaterThanOrEqualTo(_barBottom(tester)),
      );
    });

    testWidgets('on the video\'s glass, as full screen, the bar stays plain', (
      tester,
    ) async {
      // As PageUtils.showVideoBottomSheet lays the panel over the video.
      await _pump(tester, VideoGlass(radius: 24, child: _panel()));

      expect(find.byType(GlassAppBar), findsNothing);
      expect(find.byTooltip('更多'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(tester.getTopLeft(find.text('P1 第1集')).dy, lessThan(80));
    });

    testWidgets('no tabs pill for a single list', (tester) async {
      await _pump(tester, _panel());
      expect(find.byType(LiquidGlassTabBar), findsNothing);
    });
  });
}
