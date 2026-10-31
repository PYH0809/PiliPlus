import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/stat.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// The details of one video as the intro request returns them: its first
/// page's cid stays the same from one request to the next.
VideoDetailData _detail({required String title, required int like}) =>
    VideoDetailData(
      bvid: 'BV1xx411c7mD',
      aid: 1,
      cid: 100,
      title: title,
      stat: VideoStat.fromJson({'view': like * 10, 'like': like}),
    );

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-ugc-intro-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // Coming back to a video after another one failed to load fetches its
  // details again, and the intro sets them as it set the first ones.
  testWidgets('details fetched again for the same video replace the old', (
    tester,
  ) async {
    final controller = UgcIntroController()
      ..videoDetail.value = _detail(title: '旧标题', like: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Obx(() {
          final detail = controller.videoDetail.value;
          return Text('${detail.title} ${detail.stat?.like}');
        }),
      ),
    );
    expect(find.text('旧标题 1'), findsOneWidget);

    final fresh = _detail(title: '新标题', like: 2);
    controller.videoDetail.value = fresh;
    await tester.pump();

    expect(find.text('新标题 2'), findsOneWidget);
    // Likes and favourites count on the details the intro holds.
    expect(controller.videoDetail.value, same(fresh));
    expect(controller.getStat()?.like, 2);
  });
}
