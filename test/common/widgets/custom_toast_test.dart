import 'dart:io';

import 'package:PiliPlus/common/widgets/custom_toast.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// The app's toasts, over a black page standing in for the video.
Future<void> _pumpApp(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    theme: GlassSurfaces.themed(ThemeData()),
    builder: FlutterSmartDialog.init(toastBuilder: CustomToast.new),
    home: const Scaffold(backgroundColor: Colors.black),
  ),
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    GlassSurfaces.install();
    CustomToast.toastOpacity = 1;
    // The video's glass reads its mode from the settings.
    tempDir = await Directory.systemTemp.createTemp('piliplus-toast-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('a toast over the video is on the video\'s glass, eased in '
      'through its t, never under a fade', (tester) async {
    await _pumpApp(tester);
    CustomToast.showOverVideo('已跳过广告片段', alignment: const Alignment(0, 0.7));
    await tester.pump();
    // Partway in.
    await tester.pump(const Duration(milliseconds: 100));

    final glass = find.byType(VideoGlass);
    expect(glass, findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
    final t = tester.widget<VideoGlass>(glass).t;
    expect(t, inExclusiveRange(0, 1));
    // A translucent Opacity above a backdrop filter breaks it.
    for (final fade in tester.widgetList<Opacity>(
      find.ancestor(of: glass, matching: find.byType(Opacity)),
    )) {
      expect(fade.opacity, 1);
    }
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: glass, matching: find.byType(FadeTransition)),
    )) {
      expect(fade.opacity.value, 1);
    }

    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<VideoGlass>(glass).t, 1);
    expect(find.text('已跳过广告片段'), findsOneWidget);
    // Gone once shown its while.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(glass, findsNothing);
  });

  group('over the player', () {
    final player = GlobalKey();
    setUp(
      () => VideoGlassSource.player = (
        video: player,
        changes: ChangeNotifier(),
      ),
    );
    tearDown(() => VideoGlassSource.player = null);

    Future<Rect> toastAt(WidgetTester tester, {required bool video}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GlassSurfaces.themed(ThemeData()),
          builder: FlutterSmartDialog.init(toastBuilder: CustomToast.new),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(key: player),
          ),
        ),
      );
      const alignment = Alignment(0, 0.7);
      if (video) {
        CustomToast.showOverVideo('已跳过广告片段', alignment: alignment);
      } else {
        SmartDialog.showToast('已跳过广告片段', alignment: alignment);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final rect = tester.getRect(find.text('已跳过广告片段'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      return rect;
    }

    testWidgets('it draws the player\'s video, not the whole screen behind '
        'it', (tester) async {
      await _pumpApp(tester);
      CustomToast.showOverVideo('已跳过广告片段');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.ancestor(
          of: find.byType(VideoGlass),
          matching: find.byType(VideoGlassSource),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('it stands where the toast it replaces stood', (
      tester,
    ) async {
      final was = await toastAt(tester, video: false);
      final now = await toastAt(tester, video: true);
      expect((now.center.dy - was.center.dy).abs(), lessThan(1));
    });
  });

  testWidgets('elsewhere a toast keeps the toasts\' own glass', (
    tester,
  ) async {
    await _pumpApp(tester);
    SmartDialog.showToast('已复制');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(find.byType(VideoGlass), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
