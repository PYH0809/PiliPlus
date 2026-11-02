import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models/common/pgc_episode_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/section.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart'
    show BaseEpisodeItem;
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

  final picked = <int?>[];

  @override
  Future<bool> onChangeEpisode(
    BaseEpisodeItem episode, {
    PgcEpisodeType? episodeType,
    int? sectionIndex,
  }) async {
    picked.add(episode.cid);
    return true;
  }

  /// Plays [cid] as the page does: the indexes, then the cid the panels
  /// hear of.
  void play(int cid, PgcEpisodeType type, {int index = 0}) {
    episodeType = type;
    episodeIndex = type == PgcEpisodeType.episode ? index : -1;
    pvIndex = type == PgcEpisodeType.episode ? -1 : index;
    _cid.value = cid;
  }
}

PgcInfoModel _season(int id, {String prefix = 'EP'}) => PgcInfoModel(
  seasonId: id,
  episodes: [
    for (var i = 1; i <= 3; i++)
      EpisodeItem(cid: id * 100 + i, title: '$prefix$i'),
  ],
  sections: [
    Section(
      title: '预告',
      episodes: [EpisodeItem(cid: id * 10 + 1, title: 'PV')],
    ),
  ],
);

/// Lets the panel hear of what plays: it refreshes after the next frame,
/// which on the page the video changing brings about.
Future<void> _heard(WidgetTester tester) async {
  await tester.pump();
  tester.binding.scheduleFrame();
  await tester.pumpAndSettle();
}

Widget _sidePanel(_Pgc pgc) => GetMaterialApp(
  home: Scaffold(
    body: EpisodePanel(
      type: EpisodeType.pgc,
      isSidePanel: true,
      enableSlide: false,
      introController: pgc,
    ),
  ),
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-pgc-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.userInfo = await Hive.openBox('userInfo');
  });

  // The sheet's bar, plain.
  setUp(() => GlassAppBar.debugEnabled = false);
  tearDown(() => GlassAppBar.debugEnabled = null);

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

    // Its menu has nothing to jump to.
    for (final row in ['跳到底部', '跳到顶部', '跳到当前播放']) {
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: row);
    }
  });

  testWidgets('playing a pv, the side panel lets go of the episode that '
      'played, which can be picked again', (tester) async {
    final pgc = _Pgc(_season(1))..play(102, PgcEpisodeType.episode, index: 1);
    await tester.pumpWidget(_sidePanel(pgc));
    await tester.pumpAndSettle();

    pgc.play(11, PgcEpisodeType.section);
    await _heard(tester);

    await tester.tap(find.text('EP2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pgc.picked, [102]);
  });

  testWidgets('another season playing from its sections, the side panel lists '
      'that season\'s episodes', (tester) async {
    final pgc = _Pgc(_season(1))..play(101, PgcEpisodeType.episode);
    await tester.pumpWidget(_sidePanel(pgc));
    await tester.pumpAndSettle();
    expect(find.text('EP1'), findsOneWidget);

    pgc
      ..pgcItem = _season(2, prefix: '第二季 ')
      ..seasonId = 2
      ..play(21, PgcEpisodeType.section);
    await _heard(tester);

    expect(find.text('EP1'), findsNothing);
    expect(find.text('第二季 1'), findsOneWidget);
  });

  testWidgets('playing a pv, the episodes\' sheet has no current one to jump '
      'to, and leaves 跳到当前播放 be', (tester) async {
    final pgc =
        _Pgc(
            PgcInfoModel(
              seasonId: 1,
              episodes: [
                for (var i = 1; i <= 3; i++)
                  EpisodeItem(cid: 100 + i, title: '$i'),
              ],
              sections: [
                Section(
                  title: '预告',
                  episodes: [EpisodeItem(cid: 11, title: 'PV')],
                ),
              ],
            ),
          )
          // As the controller has it while a section's episode plays.
          ..episodeIndex = -1
          ..pvIndex = 0;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: EpisodePanel(
            type: EpisodeType.pgc,
            // The sheet the intro's 选集 opens, of the episodes.
            episodeType: PgcEpisodeType.episode,
            isSidePanel: false,
            enableSlide: false,
            introController: pgc,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳到当前播放'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
