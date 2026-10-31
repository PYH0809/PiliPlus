import 'dart:io';

import 'package:PiliPlus/models/common/pgc_episode_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/section.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart'
    show BaseEpisodeItem;
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/widgets/section.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// A pgc page playing from its sections, without the video page around it:
/// the section panel follows [cid] as the video page's.
class _Pgc extends PgcIntroController {
  _Pgc(PgcInfoModel item, {required int cid, required int playingSection}) {
    pgcItem = item;
    seasonId = 1;
    episodeType = PgcEpisodeType.section;
    sectionIndex = playingSection;
    _cid.value = cid;
  }

  final _cid = RxInt(0);

  @override
  RxInt get cid => _cid;
}

EpisodeItem _episode(int cid) => EpisodeItem(cid: cid, title: 'EP$cid');

PgcInfoModel _item() => PgcInfoModel(
  seasonId: 1,
  sections: [
    Section(title: '预告', episodes: [_episode(11), _episode(12)]),
    Section(title: '花絮', episodes: [_episode(21), _episode(22)]),
  ],
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-section-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.userInfo = await Hive.openBox('userInfo');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  late _Pgc pgc;
  late List<(int? cid, PgcEpisodeType? type, int? section)> picked;

  Future<void> pump(WidgetTester tester) async {
    pgc = _Pgc(_item(), cid: 11, playingSection: 0);
    picked = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionPanel(
            pgcController: pgc,
            showEpisodes: ({required type}) {},
            onChangeEpisode: (
              BaseEpisodeItem episode, {
              PgcEpisodeType? episodeType,
              int? sectionIndex,
            }) => picked.add((episode.cid, episodeType, sectionIndex)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('showing another section leaves the one playing, so next and '
      'the share still follow it', (tester) async {
    await pump(tester);
    expect(find.text('EP11'), findsOneWidget);

    await tester.tap(find.text('花絮'));
    await tester.pumpAndSettle();

    expect(find.text('EP21'), findsOneWidget);
    expect(find.text('EP11'), findsNothing);
    expect(pgc.sectionIndex, 0);
    expect(picked, isEmpty);
  });

  testWidgets('picking an episode of the section shown plays that section', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('花絮'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('EP22'));
    await tester.pumpAndSettle();

    expect(picked, [(22, PgcEpisodeType.section, 1)]);
  });

  testWidgets('as playback moves on, the panel shows the section playing', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('花絮'));
    await tester.pumpAndSettle();

    // Next, in the section playing.
    pgc.cid.value = 12;
    await tester.pumpAndSettle();

    expect(find.text('EP12'), findsOneWidget);
    expect(find.text('EP21'), findsNothing);
  });
}
