import 'dart:io';

import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
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

  testWidgets('the title bar and tabs float on glass over the list', (
    tester,
  ) async {
    putControllers();
    await tester.pumpWidget(const GetMaterialApp(home: HistoryPage()));
    await tester.pump();

    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(find.text('观看记录'), findsOneWidget);
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

    // The list starts under the bar, so it scrolls under it.
    final bar = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
    final list = find.byType(CustomScrollView).first;
    expect(
      HeaderOverlayInset.of(tester.element(list)),
      bar.preferredSize.height,
    );
    await dispose(tester);
  });

  testWidgets('without tabs the bar has no tab pill', (tester) async {
    putControllers(withTabs: false);
    await tester.pumpWidget(const GetMaterialApp(home: HistoryPage()));
    await tester.pump();

    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(find.byType(LiquidGlassTabBar), findsNothing);
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
    expect(find.byType(LiquidGlassTabBar), findsOneWidget);

    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    expect(find.text('观看记录'), findsOneWidget);
    await dispose(tester);
  });
}
