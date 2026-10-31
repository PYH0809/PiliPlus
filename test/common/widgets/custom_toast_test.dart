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

const _msg = '已切换至 1080P 高清';

final _player = GlobalKey();

/// The app's toasts over a black page, the player's video filling it.
Future<void> _pumpApp(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    theme: GlassSurfaces.themed(ThemeData()),
    builder: FlutterSmartDialog.init(toastBuilder: CustomToast.new),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(key: _player),
    ),
  ),
);

/// Shows [_msg] as a skip in full screen does, and gives where it stood.
Future<Rect> _toast(WidgetTester tester) async {
  SmartDialog.showToast(_msg, alignment: const Alignment(0, 0.7));
  await tester.pump();
  // Partway in, under SmartDialog's fade.
  await tester.pump(const Duration(milliseconds: 100));
  return tester.getRect(find.text(_msg));
}

/// Lets the toast go, once shown its while.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    GlassSurfaces.install();
    CustomToast.toastOpacity = 1;
    // The glass reads the switch and the video's glass its mode from the
    // settings.
    tempDir = await Directory.systemTemp.createTemp('piliplus-toast-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(
    () => VideoGlassSource.player = (
      video: _player,
      changes: ChangeNotifier(),
    ),
  );
  tearDown(() {
    VideoGlassSource.player = null;
    CustomToast.debugOverVideo = null;
  });

  testWidgets('in full screen a toast is on the video\'s glass, drawing the '
      'player\'s video itself, which a fade over it leaves whole', (
    tester,
  ) async {
    CustomToast.debugOverVideo = true;
    await _pumpApp(tester);
    await _toast(tester);

    final glass = find.byType(VideoGlass);
    expect(glass, findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
    // Not a backdrop filter, which a translucent fade over it would break,
    // nor a read of the whole screen every frame it shows.
    expect(
      find.ancestor(of: glass, matching: find.byType(VideoGlassSource)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text(_msg)).style?.color,
      Colors.white,
    );
    await _settle(tester);
  });

  testWidgets('it stands where the toasts\' own glass stands', (tester) async {
    await _pumpApp(tester);
    final was = await _toast(tester);
    await _settle(tester);
    CustomToast.debugOverVideo = true;
    final now = await _toast(tester);
    await _settle(tester);

    expect((now.center.dy - was.center.dy).abs(), lessThan(1));
  });

  testWidgets('out of full screen a toast keeps the toasts\' own glass', (
    tester,
  ) async {
    CustomToast.debugOverVideo = false;
    await _pumpApp(tester);
    await _toast(tester);

    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(find.byType(VideoGlass), findsNothing);
    await _settle(tester);
  });

  testWidgets('so it does with no player on screen', (tester) async {
    CustomToast.debugOverVideo = true;
    VideoGlassSource.player = null;
    await _pumpApp(tester);
    await _toast(tester);

    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(find.byType(VideoGlass), findsNothing);
    await _settle(tester);
  });
}
