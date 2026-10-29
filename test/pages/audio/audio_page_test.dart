import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart';
import 'package:PiliPlus/pages/audio/controller.dart';
import 'package:PiliPlus/pages/audio/view.dart';
import 'package:PiliPlus/pages/audio/volume_button.dart';
import 'package:PiliPlus/pages/audio/widgets/glass_controls.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/action_item.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

const _width = 412.0;
const _height = 915.0;
const _statusBar = 24.0;
const _navigationBar = 16.0;

class _FakePlayer extends Fake implements Player {
  int pauses = 0;

  @override
  final PlayerState state = PlayerState();

  @override
  String getProperty(String property) =>
      property == 'volume' ? '80.000000' : 'no';

  @override
  Future<void> pause({bool synchronized = true}) async => pauses++;

  @override
  Future<void> setVolume(double volume, {bool synchronized = true}) async {}

  @override
  Future<void> dispose() async {}
}

/// The page's controller with an item, a playlist and a player from the
/// start, which neither fetches nor plays, and notes what the page asks of
/// it.
class _FakeAudioController extends AudioController {
  _FakeAudioController({
    required this.ugc,
    required this.mv,
    this.desc = '',
  });

  final bool ugc;
  final bool mv;
  final String desc;
  final calls = <String>[];

  late final _FakePlayer fakePlayer;

  // The real one fetches the item and opens a player, which a test has
  // neither of.
  @override
  // ignore: must_call_super
  void onInit() {
    oid = Int64(170001);
    id = oid;
    subId = [Int64(1)];
    itemType = ugc ? 1 : 2;
    from = PlaylistSource.UP_ARCHIVE;
    animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    final item = DetailItem(
      arc: BKArchive(title: '一首歌', desc: desc),
      owner: Author(name: 'UP主'),
      associatedItem: mv
          ? PlayItem(oid: Int64(880001), subId: [Int64(9)])
          : null,
    );
    audioItem.value = item;
    playlist = [item];
    index = 0;
    player = fakePlayer = _FakePlayer();
    position.value = 72;
    duration.value = 225;
  }

  @override
  bool playPrev() {
    calls.add('prev');
    return true;
  }

  @override
  bool playNext({bool nextPart = false}) {
    calls.add('next');
    return true;
  }

  @override
  Future<void>? playOrPause() {
    calls.add('playOrPause');
    return null;
  }
}

/// Pumps 听视频 over a home page, with glass on or off, and routes for the
/// pages its menu opens that show where they were sent.
Future<_FakeAudioController> _pump(
  WidgetTester tester, {
  required bool glass,
  bool ugc = true,
  bool mv = false,
  String desc = '',
}) async {
  tester.view
    ..physicalSize = const Size(_width, _height)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: _statusBar, bottom: _navigationBar)
    ..viewPadding = const FakeViewPadding(
      top: _statusBar,
      bottom: _navigationBar,
    );
  addTearDown(tester.view.reset);
  GlassAppBar.debugEnabled = glass;
  final controller = _FakeAudioController(ugc: ugc, mv: mv, desc: desc);
  AudioPage.debugController = () => controller;
  await tester.pumpWidget(
    GetMaterialApp(
      home: const Scaffold(body: Text('home')),
      getPages: [
        GetPage(name: '/audio', page: () => const AudioPage()),
        GetPage(
          name: '/webview',
          page: () => Scaffold(body: Text('webview ${Get.parameters['url']}')),
        ),
        GetPage(
          name: '/videoV',
          page: () => Scaffold(
            body: Text('video ${Get.arguments['aid']} ${Get.arguments['cid']}'),
          ),
        ),
      ],
    ),
  );
  Get.toNamed('/audio');
  await tester.pumpAndSettle();
  return controller;
}

/// The pane of glass [finder] stands on.
Rect _paneUnder(WidgetTester tester, Finder finder) {
  final center = tester.getCenter(finder);
  return tester
      .widgetList(find.byType(LiquidGlass))
      .map((pane) => tester.getRect(find.byWidget(pane)))
      .firstWhere((rect) => rect.contains(center));
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-audio-page-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDown(() {
    GlassAppBar.debugEnabled = null;
    AudioPage.debugController = null;
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  for (final glass in [true, false]) {
    final mode = glass ? 'glass on' : 'glass off';

    testWidgets('$mode: no row of likes, coins, favourites, replies, shares', (
      tester,
    ) async {
      await _pump(tester, glass: glass, mv: true);

      expect(find.text('一首歌'), findsOneWidget);
      expect(find.byType(ActionItem), findsNothing);
      for (final label in ['点赞', '投币', '收藏', '评论', '分享', '看MV']) {
        expect(find.bySemanticsLabel(label), findsNothing, reason: label);
      }
    });

    testWidgets('$mode: 更多 opens a menu under the button, not a sheet', (
      tester,
    ) async {
      await _pump(tester, glass: glass);
      final button = tester.getRect(find.byTooltip('更多'));

      await _openMore(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PopupMenuItem<void>), findsWidgets);
      expect(
        tester.getRect(find.text('播放信息')).top,
        greaterThanOrEqualTo(button.top),
      );

      // A popover goes away with a tap outside it.
      await tester.tapAt(const Offset(_width / 2, _height - 300));
      await tester.pumpAndSettle();
      expect(find.text('播放信息'), findsNothing);
    });
  }

  group('更多', () {
    testWidgets('lists 看MV, 播放信息, the volume and, apart, 举报', (
      tester,
    ) async {
      await _pump(tester, glass: true, mv: true);
      await _openMore(tester);

      final rows = ['看MV', '播放信息', if (PlatformUtils.isMobile) '播放器音量: 80%'];
      var above = 0.0;
      for (final row in [...rows, '举报']) {
        final top = tester.getRect(find.text(row)).top;
        expect(top, greaterThan(above), reason: row);
        above = top;
      }
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      expect(
        tester.getRect(find.byType(PopupMenuDivider)).top,
        lessThan(tester.getRect(find.text('举报')).top),
      );
      if (!PlatformUtils.isMobile) {
        expect(find.textContaining('播放器音量'), findsNothing);
      }
    });

    testWidgets('看MV pauses and opens the MV', (tester) async {
      final controller = await _pump(tester, glass: true, mv: true);
      await _openMore(tester);

      await tester.tap(find.text('看MV'));
      await tester.pumpAndSettle();

      expect(controller.fakePlayer.pauses, 1);
      expect(find.text('video 880001 9'), findsOneWidget);
    });

    testWidgets('播放信息 shows the player\'s info', (tester) async {
      await _pump(tester, glass: true);
      await _openMore(tester);

      await tester.tap(find.text('播放信息'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Resolution'), findsOneWidget);
    });

    testWidgets('播放器音量 opens the volume dialog', (tester) async {
      await _pump(tester, glass: true);
      await _openMore(tester);

      await tester.tap(find.text('播放器音量: 80%'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('播放器音量'), findsOneWidget);
    }, skip: !PlatformUtils.isMobile);

    testWidgets('举报 opens the appeal page for the video', (tester) async {
      await _pump(tester, glass: true);
      await _openMore(tester);

      await tester.tap(find.text('举报'));
      await tester.pumpAndSettle();

      expect(
        find.text('webview https://www.bilibili.com/appeal/?avid=170001'),
        findsOneWidget,
      );
    });

    testWidgets('an audio with an MV keeps 更多 for it, without 举报', (
      tester,
    ) async {
      await _pump(tester, glass: true, ugc: false, mv: true);
      await _openMore(tester);

      expect(find.text('看MV'), findsOneWidget);
      expect(find.text('举报'), findsNothing);
      expect(find.byType(PopupMenuDivider), findsNothing);
    });

    testWidgets('an audio without an MV has no 更多', (tester) async {
      await _pump(tester, glass: true, ugc: false);

      expect(find.byTooltip('更多'), findsNothing);
      expect(find.byTooltip('排序'), findsOneWidget);
    });
  });

  group('glass on', () {
    testWidgets('the title bar\'s buttons share one capsule', (tester) async {
      await _pump(tester, glass: true);

      expect(find.byType(AppBar), findsNothing);
      final capsule = _paneUnder(tester, find.byTooltip('排序'));
      expect(_paneUnder(tester, find.byTooltip('定时关闭')), capsule);
      expect(_paneUnder(tester, find.byTooltip('更多')), capsule);
      expect(capsule.top, _statusBar + (kToolbarHeight - 44) / 2);
    });

    testWidgets('previous, play and next share a taller capsule', (
      tester,
    ) async {
      await _pump(tester, glass: true);

      final transport = _paneUnder(tester, find.byTooltip('播放'));
      expect(_paneUnder(tester, find.byTooltip('上一个')), transport);
      expect(_paneUnder(tester, find.byTooltip('下一个')), transport);
      expect(transport.height, AudioGlassControls.transportSize);

      final mode = _paneUnder(tester, find.byTooltip('播放设置'));
      final list = _paneUnder(tester, find.byTooltip('播放列表'));
      for (final circle in [mode, list]) {
        expect(circle.size, const Size.square(GlassButtonGroup.thickness));
        expect(circle.center.dy, transport.center.dy);
      }
      expect(mode.right, lessThan(transport.left));
      expect(list.left, greaterThan(transport.right));
    });

    testWidgets('the progress and its times sit on a capsule of their own', (
      tester,
    ) async {
      await _pump(tester, glass: true);

      final position = find.text(DurationUtils.formatDuration(72));
      final total = find.text(DurationUtils.formatDuration(225));
      final capsule = _paneUnder(tester, position);
      expect(_paneUnder(tester, total), capsule);
      expect(capsule.height, GlassButtonGroup.thickness);
      final transport = _paneUnder(tester, find.byTooltip('播放'));
      expect(capsule.bottom, lessThan(transport.top));
      expect(capsule.width, greaterThan(transport.width));
      // The desktop's volume is on the capsule too.
      if (PlatformUtils.isDesktop) {
        expect(_paneUnder(tester, find.byType(VolumeButton)), capsule);
      }
    });

    testWidgets('each control does what it did', (tester) async {
      final controller = await _pump(tester, glass: true);

      await tester.tap(find.byTooltip('上一个'));
      await tester.tap(find.byTooltip('播放'));
      await tester.tap(find.byTooltip('下一个'));
      expect(controller.calls, ['prev', 'playOrPause', 'next']);

      await tester.tap(find.byTooltip('播放设置'));
      await tester.pumpAndSettle();
      expect(find.text('播放倍速(1.0)'), findsOneWidget);
      await tester.tapAt(const Offset(_width / 2, 100));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('播放列表'));
      await tester.pumpAndSettle();
      expect(find.text('关闭'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('一首歌', findRichText: true),
        ),
        findsWidgets,
      );
    });

    testWidgets('the play button says pause while playing', (tester) async {
      final controller = await _pump(tester, glass: true);

      controller.animController.forward();
      await tester.pumpAndSettle();

      expect(find.byTooltip('暂停'), findsOneWidget);
      expect(find.byTooltip('播放'), findsNothing);
    });

    testWidgets('the content scrolls under the controls, its end above them', (
      tester,
    ) async {
      await _pump(
        tester,
        glass: true,
        desc: List.filled(80, '一行简介').join('\n'),
      );
      final controlsTop = _paneUnder(
        tester,
        find.text(DurationUtils.formatDuration(72)),
      ).top;
      final list = find.byType(ListView);

      // Under the controls at first, as it is longer than the page.
      expect(tester.getRect(list).bottom, _height);

      await tester.drag(list, const Offset(0, -20000));
      await tester.pumpAndSettle();
      final lastLine = tester.getRect(find.textContaining('一行简介'));
      expect(lastLine.bottom, lessThanOrEqualTo(controlsTop));
      expect(lastLine.bottom, greaterThan(controlsTop - 60));
    });

    testWidgets('a short page centers its cover between the bars', (
      tester,
    ) async {
      await _pump(tester, glass: true);
      final controlsTop = _paneUnder(
        tester,
        find.text(DurationUtils.formatDuration(72)),
      ).top;
      const barBottom = _statusBar + kToolbarHeight;

      final title = tester.getRect(find.text('一首歌'));
      expect(title.top, greaterThan(barBottom));
      expect(title.bottom, lessThan(controlsTop));
    });

    testWidgets('sideways the controls stand beside the content', (
      tester,
    ) async {
      await _pump(tester, glass: true);
      tester.view.physicalSize = const Size(_height, _width);
      await tester.pumpAndSettle();

      final transport = _paneUnder(tester, find.byTooltip('播放'));
      final title = tester.getRect(find.text('一首歌'));
      expect(transport.left, greaterThan(title.right));
      expect(transport.bottom, lessThan(_width));
    });
  });

  group('glass off', () {
    /// The row of controls under the progress, from the left.
    List<Finder> controlsRow(WidgetTester tester) {
      final row = tester.getCenter(find.byIcon(Icons.skip_next_rounded)).dy;
      final buttons = find
          .byType(IconButton)
          .evaluate()
          .where(
            (e) =>
                (tester.getCenter(find.byWidget(e.widget)).dy - row).abs() < 1,
          );
      return [
        for (final e in buttons) find.byWidget(e.widget),
      ]..sort(
        (a, b) => tester.getCenter(a).dx.compareTo(tester.getCenter(b).dx),
      );
    }

    testWidgets('keeps Material\'s bar and its row of five controls', (
      tester,
    ) async {
      final controller = await _pump(tester, glass: false);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.byType(AudioGlassControls), findsNothing);

      final row = controlsRow(tester);
      expect(row, hasLength(5));
      final [mode, prev, play, next, list] = row;
      expect(
        find.descendant(of: play, matching: find.byType(AnimatedIcon)),
        findsOneWidget,
      );

      await tester.tap(prev);
      await tester.tap(play);
      await tester.tap(next);
      expect(controller.calls, ['prev', 'playOrPause', 'next']);

      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(find.text('播放倍速(1.0)'), findsOneWidget);
      await tester.tapAt(const Offset(_width / 2, 100));
      await tester.pumpAndSettle();

      await tester.tap(list);
      await tester.pumpAndSettle();
      expect(find.text('关闭'), findsOneWidget);
    });

    testWidgets('the progress and its times stay above the row', (
      tester,
    ) async {
      await _pump(tester, glass: false);

      final row = tester.getRect(controlsRow(tester).first);
      final position = tester.getRect(
        find.text(DurationUtils.formatDuration(72)),
      );
      expect(position.bottom, lessThanOrEqualTo(row.top));
      expect(find.byType(ProgressBar), findsOneWidget);
      expect(
        tester.getRect(find.byType(ProgressBar)).bottom,
        lessThanOrEqualTo(position.top),
      );
    });
  });
}
