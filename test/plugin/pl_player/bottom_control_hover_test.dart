import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/bottom_control.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// The player, as much of it as the bottom bar reads while hovered.
class _Player extends Fake implements PlPlayerController {
  @override
  int get progress => position.value;
  @override
  final RxInt position = RxInt(30);
  @override
  final RxInt buffered = RxInt(0);
  @override
  final RxInt duration = RxInt(600);
  @override
  final RxInt seekPosition = RxInt(0);
  @override
  final RxBool showControls = true.obs;
  @override
  final RxBool isSeeking = false.obs;
  @override
  final RxBool showPreview = false.obs;
  @override
  bool get enableBlock => false;
  @override
  bool get showViewPoints => false;
  @override
  bool get showSeekPreview => true;
  @override
  bool get isFileSource => false;
  @override
  double? hoverDx;

  @override
  void updatePreviewIndex(int seconds) {}
  @override
  void onSeekStart(int seekFrom) => isSeeking.value = true;
  @override
  void onSeekEnd() => isSeeking.value = false;
  @override
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {}
  @override
  void hideTaskControls() {}
}

class _Video extends Fake implements VideoDetailController {
  @override
  late final RxBool showDmTrendChart = false.obs;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    enableFeedback = false;
    tempDir = await Directory.systemTemp.createTemp('piliplus-bottom-control-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  late _Player player;

  /// The bar along the bottom of a [width] wide player, laid as the player
  /// lays it: from its left edge.
  Future<void> pump(
    WidgetTester tester, {
    double width = 800,
    bool isFullScreen = false,
  }) async {
    tester.view
      ..physicalSize = Size(width, 450)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    player = _Player();
    final anim = AnimationController(vsync: const TestVSync(), value: 1);
    addTearDown(anim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomLeft,
            child: BottomControl(
              maxWidth: width,
              isFullScreen: isFullScreen,
              animCtr: anim,
              controller: player,
              videoDetailController: _Video(),
              buildBottomControl: () => const SizedBox(height: 40),
            ),
          ),
        ),
      ),
    );
  }

  /// Hovers [fraction] of the way along the bar, and returns where the
  /// pointer is across the player.
  Future<double> hover(
    WidgetTester tester,
    TestGesture mouse,
    double fraction,
  ) async {
    final bar = tester.getRect(find.byType(ProgressBar));
    final at = Offset(bar.left + bar.width * fraction, bar.center.dy);
    await mouse.moveTo(at);
    await tester.pump();
    return at.dx;
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    return mouse;
  }

  // The preview stands over the pointer by taking the hover as the plain
  // bar has it, 20 dp in from the player's edge.
  const plainBarLeft = 20.0;

  testWidgets('plain, the hover is told from where the bar starts', (
    tester,
  ) async {
    await pump(tester);
    expect(
      tester.getTopLeft(find.byType(ProgressBar)).dx,
      plainBarLeft,
    );
    final x = await hover(tester, await mouse(tester), 0.4);
    expect(player.hoverDx, closeTo(x - plainBarLeft, 0.01));
  });

  group('on glass', () {
    // Installing only ever turns glass on, so these come after the plain one.
    setUpAll(GlassSurfaces.install);

    testWidgets('the bar starts further in, after the time on the pane, and '
        'the hover is told as the plain bar would have it', (tester) async {
      await pump(tester);
      expect(
        tester.getTopLeft(find.byType(ProgressBar)).dx,
        greaterThan(plainBarLeft + 20),
      );
      final x = await hover(tester, await mouse(tester), 0.4);
      expect(player.hoverDx, closeTo(x - plainBarLeft, 0.01));
    });

    testWidgets('full screen, where the pane stands a tenth of the width in', (
      tester,
    ) async {
      await pump(tester, width: 1600, isFullScreen: true);
      expect(tester.getTopLeft(find.byType(ProgressBar)).dx, greaterThan(160));
      final x = await hover(tester, await mouse(tester), 0.7);
      expect(player.hoverDx, closeTo(x - plainBarLeft, 0.01));
    });

    testWidgets('pressed and dragged on from a hover, the preview follows the '
        'pointer still', (tester) async {
      await pump(tester);
      final pointer = await mouse(tester);
      final from = await hover(tester, pointer, 0.3);
      await pointer.down(
        Offset(from, tester.getCenter(find.byType(ProgressBar)).dy),
      );
      await tester.pump();
      final bar = tester.getRect(find.byType(ProgressBar));
      final to = bar.left + bar.width * 0.6;
      await pointer.moveTo(Offset(to, bar.center.dy));
      await tester.pump();
      expect(player.hoverDx, closeTo(to - plainBarLeft, 0.01));
      await pointer.up();
      await tester.pump();
    });
  });
}
