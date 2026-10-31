import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_detail/section.dart';
import 'package:PiliPlus/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliPlus/pages/episode_panel/view.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

EpisodeItem _episode(int cid) => EpisodeItem(
  aid: cid,
  cid: cid,
  bvid: 'BV$cid',
  title: 'EP$cid',
  pages: [Part(cid: cid, page: 1)],
);

/// A video of the season [id], in [sections] sections of two episodes.
VideoDetailData _video(int id, int sections, {int? topSeasonId}) =>
    VideoDetailData(
      aid: 1,
      bvid: 'BV1',
      // Its own cid: VideoDetailData is equal by it.
      cid: id * 100,
      seasonId: topSeasonId,
      ugcSeason: UgcSeason(
        id: id,
        sections: [
          for (var s = 0; s < sections; s++)
            SectionItem(
              title: '第${s + 1}部',
              episodes: [
                _episode(id * 100 + s * 2),
                _episode(id * 100 + s * 2 + 1),
              ],
            ),
        ],
      ),
    );

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-season-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.userInfo = await Hive.openBox('userInfo');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() => GlassAppBar.debugEnabled = false);
  tearDown(() => GlassAppBar.debugEnabled = null);

  Future<void> pump(WidgetTester tester, Widget panel) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(home: Scaffold(body: panel)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('built anew for another season, as the page does, its jumps '
      'go to its own list', (tester) async {
    final ugc = UgcIntroController()..videoDetail.value = _video(1, 1);
    final season = ValueNotifier(1);
    addTearDown(season.dispose);
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          // As the page's side panel: keyed by the season it shows.
          body: ValueListenableBuilder(
            valueListenable: season,
            builder: (context, id, _) => EpisodePanel(
              key: ValueKey(id),
              type: EpisodeType.season,
              isSidePanel: true,
              enableSlide: false,
              introController: ugc,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Played on into another season of one section.
    ugc.videoDetail.value = _video(2, 1);
    season.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('EP200'), findsOneWidget);

    for (final row in ['跳到底部', '跳到顶部', '跳到当前播放']) {
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: row);
    }
  });

  testWidgets('a sheet opened before playing all moved on into a longer '
      'season leaves 跳到当前播放 be', (tester) async {
    final ugc = _Ugc()..videoDetail.value = _video(1, 1);
    await pump(
      tester,
      EpisodePanel(
        type: EpisodeType.season,
        isSidePanel: false,
        enableSlide: false,
        introController: ugc,
      ),
    );

    // On into a season whose current episode lies past the sheet's list.
    ugc.videoDetail.value = VideoDetailData(
      aid: 3,
      bvid: 'BV3',
      cid: 300,
      ugcSeason: UgcSeason(
        id: 3,
        sections: [
          SectionItem(
            episodes: [for (var i = 0; i < 6; i++) _episode(300 + i)],
          ),
        ],
      ),
    );
    ugc.playing = 5;
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳到当前播放'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('logged in, a season without the video\'s top-level '
      'season_id still offers its subscription', (tester) async {
    final mode = Accounts.accountMode;
    final before = mode[AccountType.main.index];
    mode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'csrf'}),
      'access-key',
      'refresh-token',
    );
    addTearDown(() => mode[AccountType.main.index] = before);
    final ugc = UgcIntroController()
      ..videoDetail.value = _video(5, 2)
      // Known already, so that the panel asks no one.
      ..seasonFavState[5] = true;

    await pump(
      tester,
      EpisodePanel(
        type: EpisodeType.season,
        isSidePanel: true,
        enableSlide: false,
        introController: ugc,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.text('取消订阅合集'), findsOneWidget);
  });

  testWidgets('an episode tapped is picked at once, the panel closing '
      'itself over the page, which stays; a second tap meanwhile is let be', (
    tester,
  ) async {
    final ugc = _Ugc()..videoDetail.value = _video(1, 1);
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: Text('video'))),
    );
    Get.to<void>(
      () => Scaffold(
        body: EpisodePanel(
          type: EpisodeType.season,
          isSidePanel: false,
          enableSlide: false,
          introController: ugc,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('EP101'));
    await tester.pump();
    expect(ugc.picked, [101]);
    // A second tap as it closes.
    await tester.tap(find.text('EP100'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(ugc.picked, [101]);
    expect(find.byType(EpisodePanel), findsNothing);
    expect(find.text('video'), findsOneWidget);
  });
}

/// Notes what is picked, in place of loading it, and plays the episode
/// [playing] of its season.
class _Ugc extends UgcIntroController {
  final picked = <int?>[];
  int playing = 0;

  @override
  int get seasonIndex => playing;

  @override
  Future<bool> onChangeEpisode(
    BaseEpisodeItem episode, {
    bool isStein = false,
  }) async {
    picked.add(episode.cid);
    return true;
  }
}
