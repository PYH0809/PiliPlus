import 'dart:io';

import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models/common/pgc_episode_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/section.dart';
import 'package:PiliPlus/pages/episode_panel/view.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// A pgc page without the video page around it, [cid] standing for the
/// video page's.
class _Pgc extends PgcIntroController {
  _Pgc(PgcInfoModel item) {
    pgcItem = item;
    seasonId = 1;
    episodeType = PgcEpisodeType.section;
  }

  final _cid = RxInt(11);

  @override
  RxInt get cid => _cid;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-pgc-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.userInfo = await Hive.openBox('userInfo');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('a season with sections but no episodes opens the side panel '
      'empty, rather than throwing', (tester) async {
    final pgc = _Pgc(
      PgcInfoModel(
        seasonId: 1,
        sections: [
          Section(
            title: '预告',
            episodes: [EpisodeItem(cid: 11, title: 'PV')],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: EpisodePanel(
            type: EpisodeType.pgc,
            isSidePanel: true,
            enableSlide: false,
            introController: pgc,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Playing on in the sections, as the panel hears of it.
    pgc.cid.value = 12;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('更多'), findsOneWidget);
  });
}
