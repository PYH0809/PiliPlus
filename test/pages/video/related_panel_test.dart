import 'dart:io';

import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/video/related/controller.dart';
import 'package:PiliPlus/pages/video/related/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

HotVideoItemModel _item(int aid) => .fromJson({
  'aid': aid,
  'cid': aid + 100,
  'bvid': 'BV1xx411c7mD',
  'title': '视频 $aid',
  'pubdate': 0,
  'duration': 60,
  'owner': {'mid': 1, 'name': 'UP'},
  'stat': {'view': 1, 'danmaku': 1},
});

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-related-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  tearDown(Get.reset);

  Future<RelatedController> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(400, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late RelatedController controller;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) {
            Get.routing.args = {'bvid': 'BV1xx411c7mD'};
            controller = Get.put(
              RelatedController(autoQuery: false),
              tag: 'tag',
            );
            return const Scaffold(
              body: CustomScrollView(
                slivers: [RelatedVideoPanel(heroTag: 'tag')],
              ),
            );
          },
        ),
      ),
    );
    return controller;
  }

  testWidgets('the cards come a couple a frame over their placeholders', (
    tester,
  ) async {
    final controller = await pump(tester);
    controller.loadingState.value = Success([
      for (var i = 0; i < 12; i++) _item(i + 1),
    ]);
    await tester.pump();
    // The list's frame: none built yet, each in its place all the same.
    expect(find.byType(VideoCardH), findsNothing);
    double extent() => tester
        .renderObject<RenderSliver>(find.byType(SliverGrid))
        .geometry!
        .scrollExtent;
    final placeholders = extent();
    expect(placeholders, greaterThan(0));

    await tester.pump();
    expect(find.byType(VideoCardH), findsNWidgets(2));
    await tester.pump();
    expect(find.byType(VideoCardH), findsNWidgets(4));
    await tester.pump();
    expect(find.byType(VideoCardH), findsNWidgets(6));
    // Past the first few, the rest at once.
    await tester.pump();
    expect(find.byType(VideoCardH), findsNWidgets(12));
    expect(extent(), placeholders);
    expect(find.text('视频 12'), findsOneWidget);
  });

  testWidgets('a card removed keeps the others built', (tester) async {
    final controller = await pump(tester);
    controller.loadingState.value = Success([
      for (var i = 0; i < 3; i++) _item(i + 1),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(VideoCardH), findsNWidgets(3));
    controller.loadingState
      ..value.data!.removeAt(0)
      ..refresh();
    await tester.pump();
    expect(find.byType(VideoCardH), findsNWidgets(2));
    expect(find.text('视频 1'), findsNothing);
    expect(find.text('视频 2'), findsOneWidget);
  });
}
