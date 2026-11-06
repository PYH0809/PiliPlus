import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/history/tab.dart';
import 'package:PiliPlus/pages/history/controller.dart';
import 'package:PiliPlus/pages/history/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// A history list that asks the network for nothing: its tabs and an empty
/// page stand ready, as after the first load.
class _FakeHistoryController extends HistoryController {
  _FakeHistoryController(super.type, {this.withTabs = true});

  final bool withTabs;

  @override
  Future<void> historyStatus() async {}

  @override
  Future<void> queryData([bool isRefresh = true]) async {}

  @override
  void onInit() {
    super.onInit();
    if (type == null && withTabs) {
      tabs.value = [
        HistoryTab(type: 'archive', name: '视频'),
        HistoryTab(type: 'live', name: '直播'),
        HistoryTab(type: 'article', name: '专栏'),
      ];
      tabController = TabController(length: tabs.length + 1, vsync: this);
    }
    loadingState.value = const Success(null);
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-history-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() => GlassAppBar.debugEnabled = true);
  tearDown(() {
    GlassAppBar.debugEnabled = null;
    Get.reset();
  });

  // Lets the page's timers, as the glass morph's, run out.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  void putControllers({bool withTabs = true}) {
    Get.put<HistoryController>(
      _FakeHistoryController(null, withTabs: withTabs),
      tag: 'all',
    );
    for (final type in ['archive', 'live', 'article']) {
      Get.put<HistoryController>(_FakeHistoryController(type), tag: type);
    }
  }

  testWidgets('the tabs take the title\'s place on the glass bar', (
    tester,
  ) async {
    putControllers();
    await tester.pumpWidget(const GetMaterialApp(home: HistoryPage()));
    await tester.pump();

    expect(find.byType(GlassAppBar), findsOneWidget);
    // One row: the tabs stand where the title would, beside the buttons.
    expect(find.text('观看记录'), findsNothing);
    final bar = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
    expect(bar.tabs, isNull);
    expect(bar.preferredSize.height, kToolbarHeight);
    final pill = tester.getRect(find.byType(LiquidGlassTabBar));
    expect(
      pill.center.dy,
      moreOrLessEquals(tester.getCenter(find.byTooltip('搜索')).dy),
    );
    expect(pill.right, lessThan(tester.getRect(find.byTooltip('搜索')).left));
    final tabs = tester.widget<LiquidGlassTabBar>(
      find.byType(LiquidGlassTabBar),
    );
    expect(tabs.labels, ['全部', '视频', '直播', '专栏']);
    // No Material tab bar of its own under the glass one.
    expect(
      find.descendant(
        of: find.byType(TabBarView),
        matching: find.byType(TabBar),
      ),
      findsNothing,
    );

    // The 全部 list leaves room for the bar at its top, so its first rows
    // start under the bar and scroll under it.
    final space = find.descendant(
      of: find.byType(SliverHeaderOverlaySpace).first,
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(space).height, bar.preferredSize.height);
    await dispose(tester);
  });

  testWidgets('without tabs the bar shows the title', (tester) async {
    putControllers(withTabs: false);
    await tester.pumpWidget(const GetMaterialApp(home: HistoryPage()));
    await tester.pump();

    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(find.byType(LiquidGlassTabBar), findsNothing);
    expect(find.text('观看记录'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('picking turns the glass bar into the multi-select one', (
    tester,
  ) async {
    putControllers();
    await tester.pumpWidget(const GetMaterialApp(home: HistoryPage()));
    await tester.pump();

    Get.find<HistoryController>(tag: 'all').enableMultiSelect.value = true;
    await tester.pump();

    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(find.text('已选: 0'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
    // As tall as before, so the list doesn't move.
    expect(
      tester.widget<GlassAppBar>(find.byType(GlassAppBar)).preferredSize,
      const Size.fromHeight(kToolbarHeight),
    );

    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    expect(find.byType(LiquidGlassTabBar), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('on a 360 dp phone every tab shows without scrolling', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    putControllers();
    // Opened over another page, so it has its back button, as in the app.
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
    Get.to<void>(() => const HistoryPage());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);

    final pill = tester.getRect(find.byType(LiquidGlassTabBar));
    for (final label in ['全部', '视频', '直播', '专栏']) {
      final tab = tester.getRect(find.text(label));
      expect(tab.left, greaterThanOrEqualTo(pill.left), reason: label);
      expect(tab.right, lessThanOrEqualTo(pill.right), reason: label);
    }
    await dispose(tester);
  });

  testWidgets('the tabs still name the page to a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    putControllers();
    await tester.pumpWidget(const GetMaterialApp(home: HistoryPage()));
    await tester.pump();

    expect(
      tester.getSemantics(find.bySemanticsLabel('观看记录')),
      isSemantics(label: '观看记录', isHeader: true, namesRoute: true),
    );
    semantics.dispose();
    await dispose(tester);
  });
}
