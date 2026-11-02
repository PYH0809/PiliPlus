import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// The video page, as much of it as the parts panel reads.
class _Video extends Fake implements VideoDetailController {
  @override
  String bvid = 'BV1xx411c7mD';
}

/// A video of [parts] parts playing its third, without the video page
/// around it.
class _Ugc extends UgcIntroController {
  _Ugc(int parts) {
    videoDetail.value = VideoDetailData(
      bvid: 'BV1xx411c7mD',
      pages: [
        for (var i = 1; i <= parts; i++) Part(cid: i, page: i, part: 'P$i'),
      ],
    );
  }

  final _video = _Video();

  @override
  VideoDetailController get videoDetailCtr => _video;

  @override
  int get partIndex => 2;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-page-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('on the side panel, without its list, it opens on a later part '
      'without scrolling', (tester) async {
    // As the side panel shows a season's video of parts: a header only.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagePanel(
            showList: false,
            showEpisodes: ({required type, episodeType}) {},
            ugcIntroController: _Ugc(5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(' 正在播放：P3'), findsOneWidget);
    expect(find.text('共5集'), findsOneWidget);
  });

  testWidgets('with its list, it opens scrolled to the part playing', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(300, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagePanel(ugcIntroController: _Ugc(20)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(list.position.pixels, greaterThan(0));
    // The third part, by its number, in sight.
    final third = tester.getRect(find.text('3'));
    expect(third.left, greaterThanOrEqualTo(0));
    expect(third.right, lessThanOrEqualTo(300));
  });
}
