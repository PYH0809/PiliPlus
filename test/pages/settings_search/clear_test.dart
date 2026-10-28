import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/pages/settings_search/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'piliplus-settings-search-',
    );
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.video = await Hive.openBox('video');
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

  testWidgets('clearing right after typing leaves no results', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: SettingsSearchPage()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '弹幕');
    await tester.pump(const Duration(milliseconds: 50));
    // Within the 200 ms debounce.
    await tester.tap(find.byTooltip('清除'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(SliverMasonryGrid), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });
}
