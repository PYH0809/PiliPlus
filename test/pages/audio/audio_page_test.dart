import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/pages/audio/controller.dart';
import 'package:PiliPlus/pages/audio/subtitle/lyrics_list.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_view.dart';
import 'package:PiliPlus/pages/audio/view.dart';
import 'package:PiliPlus/pages/audio/volume_button.dart';
import 'package:PiliPlus/pages/audio/widgets/glass_controls.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/action_item.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

  // Fetches no subtitles: they are there or not as a test sets them.
  @override
  (int, int)? get subtitleTarget => null;

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

  @override
  Future<void>? onSeek(Duration duration) {
    calls.add('seek ${duration.inSeconds}');
    return null;
  }

  @override
  Future<void>? onPlay() {
    calls.add('play');
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
  ThemeData? theme,
  Size size = const Size(_width, _height),
}) async {
  tester.view
    ..physicalSize = size
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
      theme: theme,
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

/// 80 lines two seconds apart, the 36th playing.
void _setLines(_FakeAudioController controller) {
  controller.subtitleLines.value = Success([
    for (var i = 0; i < 80; i++)
      SubtitleLine(
        from: Duration(seconds: i * 2),
        to: Duration(seconds: i * 2 + 1),
        content: '第 $i 句',
      ),
  ]);
  controller.updateSubtitlePosition(const Duration(seconds: 72));
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

  testWidgets('glass on, light theme: the menus read light on the dark page', (
    tester,
  ) async {
    await _pump(
      tester,
      glass: true,
      theme: GlassSurfaces.themed(ThemeData(brightness: Brightness.light)),
    );
    await _openMore(tester);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('播放信息'),
    );
    expect(paragraph.text.style!.color!.computeLuminance(), greaterThan(0.5));
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

    testWidgets('看MV opens the MV of the track playing when it is picked', (
      tester,
    ) async {
      final controller = await _pump(tester, glass: true, mv: true);
      await _openMore(tester);

      // The next track starts while the menu is open.
      controller.audioItem.value = DetailItem(
        arc: BKArchive(title: '下一首'),
        associatedItem: PlayItem(oid: Int64(880002), subId: [Int64(10)]),
      );
      await tester.tap(find.text('看MV'));
      await tester.pumpAndSettle();

      expect(controller.fakePlayer.pauses, 1);
      expect(find.text('video 880002 10'), findsOneWidget);
    });

    testWidgets('看MV does nothing once the track playing has none', (
      tester,
    ) async {
      final controller = await _pump(tester, glass: true, mv: true);
      await _openMore(tester);

      controller.audioItem.value = DetailItem(arc: BKArchive(title: '下一首'));
      await tester.tap(find.text('看MV'));
      await tester.pumpAndSettle();

      expect(controller.fakePlayer.pauses, 0);
      expect(find.textContaining('video'), findsNothing);
      expect(find.text('下一首'), findsOneWidget);
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

    testWidgets('the progress drags from anywhere on its capsule', (
      tester,
    ) async {
      final controller = await _pump(tester, glass: true);
      final capsule = _paneUnder(
        tester,
        find.text(DurationUtils.formatDuration(72)),
      );
      final bar = tester.getRect(find.byType(ProgressBar));
      expect(bar.height, lessThan(capsule.height / 2));

      // Above the bar's line, then below it, near the capsule's edges.
      for (final y in [capsule.top + 6, capsule.bottom - 6]) {
        controller.calls.clear();
        await tester.dragFrom(
          Offset(bar.left + 10, y),
          Offset(bar.width / 2, 0),
        );
        await tester.pumpAndSettle();
        expect(controller.calls, hasLength(1), reason: 'at $y');
        expect(controller.calls.single, startsWith('seek '));
        // Halfway along 225 s, give or take the thumb.
        final seconds = int.parse(controller.calls.single.split(' ').last);
        expect(seconds, inInclusiveRange(100, 140), reason: 'at $y');
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

  group('subtitles', () {
    final cover = find.byWidgetPredicate(
      (widget) => widget is NetworkImgLayer && widget.width == 170,
    );

    for (final glass in [true, false]) {
      final mode = glass ? 'glass on' : 'glass off';

      testWidgets('$mode: the cover shows them, the title above goes back', (
        tester,
      ) async {
        final controller = await _pump(tester, glass: glass);
        await tester.tap(cover);
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isTrue);
        expect(find.text('暂无字幕'), findsOneWidget);
        expect(cover, findsNothing);

        await tester.tap(find.text('一首歌'));
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isFalse);
        expect(cover, findsOneWidget);
      });

      testWidgets('$mode: no 字幕 button in the title bar', (tester) async {
        await _pump(tester, glass: glass);
        expect(find.byTooltip('字幕'), findsNothing);
        expect(find.byIcon(Icons.subtitles_outlined), findsNothing);
      });

      testWidgets('$mode: a tap on the room around the cover shows them, '
          'and one beside a line or on no lines goes back', (tester) async {
        final controller = await _pump(tester, glass: glass);
        // Beside the cover, on nothing of its own.
        await tester.tapAt(Offset(_width - 32, tester.getCenter(cover).dy));
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isTrue);
        expect(find.byType(AudioSubtitlePanel), findsOneWidget);

        // 暂无字幕 and the room about it.
        await tester.tap(find.text('暂无字幕'));
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isFalse);
        expect(cover, findsOneWidget);

        await tester.tap(cover);
        await tester.pumpAndSettle();
        _setLines(controller);
        await tester.pumpAndSettle();
        final line = tester.getRect(find.text('第 36 句'));
        await tester.tapAt(Offset(_width - 32, line.center.dy));
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isFalse);
        expect(controller.calls, isEmpty);
      });

      testWidgets('$mode: a tap between two lines goes back', (tester) async {
        final controller = await _pump(tester, glass: glass);
        await tester.tap(cover);
        await tester.pumpAndSettle();
        _setLines(controller);
        await tester.pumpAndSettle();
        final above = tester.getRect(find.text('第 36 句'));
        final below = tester.getRect(find.text('第 37 句'));
        await tester.tapAt(
          Offset(above.left + 8, (above.bottom + below.top) / 2),
        );
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isFalse);
        expect(controller.calls, isEmpty);
      });

      testWidgets('$mode: a tap on a line plays from it, the lines staying', (
        tester,
      ) async {
        final controller = await _pump(tester, glass: glass);
        await tester.tap(cover);
        await tester.pumpAndSettle();
        _setLines(controller);
        await tester.pumpAndSettle();
        await tester.tap(find.text('第 37 句'));
        await tester.pumpAndSettle();
        expect(controller.calls, contains('seek 74'));
        expect(controller.showSubtitle.value, isTrue);
      });

      testWidgets('$mode: a drag on the lines scrolls them, the lines '
          'staying', (tester) async {
        final controller = await _pump(tester, glass: glass);
        await tester.tap(cover);
        await tester.pumpAndSettle();
        _setLines(controller);
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(find.text('第 40 句')).dy;
        final line = tester.getRect(find.text('第 36 句'));
        await tester.dragFrom(
          Offset(_width - 32, line.center.dy),
          const Offset(0, -160),
        );
        await tester.pump();
        expect(tester.getTopLeft(find.text('第 40 句')).dy, lessThan(before));
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isTrue);
        expect(controller.calls, isEmpty);
      });

      testWidgets('$mode: a tap that stops the lines scrolling stays', (
        tester,
      ) async {
        final controller = await _pump(tester, glass: glass);
        await tester.tap(cover);
        await tester.pumpAndSettle();
        _setLines(controller);
        await tester.pumpAndSettle();
        final list = tester.getRect(find.byType(AudioSubtitleList));
        await tester.flingFrom(
          Offset(_width - 32, list.center.dy),
          const Offset(0, -300),
          2000,
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(Offset(_width - 32, list.center.dy));
        await tester.pumpAndSettle();
        expect(controller.showSubtitle.value, isTrue);
      });
    }

    testWidgets('glass on: a tap on the title bar or between the controls '
        'does not switch', (tester) async {
      final controller = await _pump(tester, glass: true);
      // Between the back button and the capsule of buttons.
      await tester.tapAt(const Offset(_width / 2, _statusBar + 28));
      await tester.pumpAndSettle();
      expect(controller.showSubtitle.value, isFalse);
      // Beside the round buttons, between the capsules.
      final progress = _paneUnder(
        tester,
        find.text(DurationUtils.formatDuration(72)),
      );
      await tester.tapAt(Offset(_width / 2, progress.bottom + 3));
      await tester.pumpAndSettle();
      expect(controller.showSubtitle.value, isFalse);
    });

    testWidgets('glass on, sideways: a tap beside the cover shows them', (
      tester,
    ) async {
      final controller = await _pump(
        tester,
        glass: true,
        size: const Size(_height, _width),
      );
      final rect = tester.getRect(cover);
      await tester.tapAt(Offset(rect.left - 24, rect.center.dy));
      await tester.pumpAndSettle();
      expect(controller.showSubtitle.value, isTrue);
      await tester.tap(find.text('暂无字幕'));
      await tester.pumpAndSettle();
      expect(controller.showSubtitle.value, isFalse);
    });

    testWidgets('a screen reader finds the switch as a button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = await _pump(tester, glass: true);
      final toggle = find.byType(AudioSubtitleToggle);
      expect(
        tester.getSemantics(toggle),
        isSemantics(label: '显示字幕', isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('显示字幕'));
      await tester.pumpAndSettle();
      expect(controller.showSubtitle.value, isTrue);
      expect(
        tester.getSemantics(toggle),
        isSemantics(label: '显示封面', isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('an audio switches only on its cover, as before', (
      tester,
    ) async {
      final controller = await _pump(tester, glass: true, ugc: false);
      expect(find.byType(AudioSubtitleToggle), findsNothing);
      await tester.tapAt(Offset(_width - 32, tester.getCenter(cover).dy));
      await tester.pumpAndSettle();
      expect(controller.showSubtitle.value, isFalse);
    });

    testWidgets('an audio has no 字幕 button, and no subtitles', (
      tester,
    ) async {
      await _pump(tester, glass: true, ugc: false);
      expect(find.byTooltip('字幕'), findsNothing);

      await tester.tap(cover);
      await tester.pumpAndSettle();
      expect(find.text('暂无字幕'), findsOneWidget);
    });

    testWidgets('glass on: the lines stay between the title bar and the '
        'controls', (tester) async {
      final controller = await _pump(tester, glass: true);
      await tester.tap(cover);
      await tester.pumpAndSettle();
      controller.subtitleLines.value = Success([
        for (var i = 0; i < 80; i++)
          SubtitleLine(
            from: Duration(seconds: i * 2),
            to: Duration(seconds: i * 2 + 1),
            content: '第 $i 句',
          ),
      ]);
      controller.updateSubtitlePosition(const Duration(seconds: 72));
      await tester.pumpAndSettle();
      final controlsTop = _paneUnder(
        tester,
        find.text(DurationUtils.formatDuration(72)),
      ).top;
      const barBottom = _statusBar + kToolbarHeight;

      final header = tester.getRect(find.text('一首歌'));
      expect(header.top, greaterThanOrEqualTo(barBottom));
      final list = tester.getRect(find.byType(AudioSubtitleList));
      expect(list.top, greaterThan(header.bottom));
      expect(list.bottom, lessThanOrEqualTo(controlsTop));
      // the line 72 seconds in, its top 8% down them
      expect(controller.subtitleLine.value, 36);
      expect(
        tester.getTopLeft(find.text('第 36 句')).dy,
        moreOrLessEquals(list.top + list.height * Lyrics.anchor, epsilon: 1),
      );
    });
  });
}
