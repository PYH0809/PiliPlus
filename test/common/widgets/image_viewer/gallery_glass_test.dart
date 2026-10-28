import 'dart:io';

import 'package:PiliPlus/common/widgets/gesture/image_horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/image_viewer/gallery_glass.dart';
import 'package:PiliPlus/common/widgets/image_viewer/hero_dialog_route.dart';
import 'package:PiliPlus/common/widgets/image_viewer/viewer.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: child),
  ),
);

void main() {
  // The viewer's gestures and the route read settings through Pref; the
  // glass switch is on by default.
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-gallery-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('GalleryGlass', () {
    late AnimationController drag;
    late ValueNotifier<bool> zoomed;

    setUp(() {
      drag = AnimationController(vsync: const TestVSync());
      zoomed = ValueNotifier(false);
    });
    tearDown(() {
      drag.dispose();
      zoomed.dispose();
    });

    Widget glass() => _app(
      GalleryGlass(drag: drag, zoomed: zoomed, child: const Text('3/9')),
    );

    testWidgets('holds the page count on glass at rest', (tester) async {
      await tester.pumpWidget(glass());
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(find.text('3/9'), findsOneWidget);
    });

    testWidgets('steps aside as the image is pulled to close', (
      tester,
    ) async {
      await tester.pumpWidget(glass());

      drag.value = 0.05;
      await tester.pump();
      expect(find.byType(LiquidGlass), findsOneWidget);

      drag.value = 0.1;
      await tester.pump();
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.text('3/9'), findsNothing);

      // The image snaps back.
      drag.value = 0;
      await tester.pump();
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('steps aside while zoomed in, and comes back', (
      tester,
    ) async {
      await tester.pumpWidget(glass());

      zoomed.value = true;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(LiquidGlass), findsOneWidget, reason: 'springs out');
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlass), findsNothing);

      zoomed.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('jumps with animations off', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: glass(),
        ),
      );
      zoomed.value = true;
      await tester.pump();
      expect(find.byType(LiquidGlass), findsNothing);
    });
  });

  testWidgets('Viewer reports whether it is zoomed in', (tester) async {
    final doubleTap = DoubleTapGestureRecognizer();
    final horizontalDrag = ImageHorizontalDragGestureRecognizer();
    addTearDown(doubleTap.dispose);
    addTearDown(horizontalDrag.dispose);
    final reports = <bool>[];

    await tester.pumpWidget(
      _app(
        NotificationListener<ViewerZoomNotification>(
          onNotification: (notification) {
            reports.add(notification.zoomed);
            return true;
          },
          child: SizedBox(
            width: 400,
            height: 800,
            child: Viewer(
              minScale: 1,
              maxScale: 8,
              containerSize: const Size(400, 800),
              childSize: const Size(400, 300),
              onDragStart: null,
              onDragUpdate: null,
              onDragEnd: null,
              doubleTapGestureRecognizer: doubleTap,
              horizontalDragGestureRecognizer: horizontalDrag,
              // Without pages to turn, the wheel zooms.
              onChangePage: null,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    expect(reports, [false], reason: 'once as it first shows');

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(Viewer));
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(reports, [false, true]);

    // Still zoomed: nothing new to tell.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(reports, [false, true]);

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 1000)));
    await tester.pump();
    expect(reports, [false, true, false]);
  });

  group('HeroDialogRoute', () {
    testWidgets('fades the gallery as a layer the glass bends through', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox.expand()),
      );
      navigator.currentState!.push<void>(
        HeroDialogRoute(
          pageBuilder: (_, _, _) => const Center(
            child: LiquidGlass(
              style: LiquidGlassStyle(tint: Colors.white),
              child: SizedBox(width: 80, height: 32),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final glass = find.byType(LiquidGlass);
      expect(
        find.ancestor(of: glass, matching: find.byType(LiquidGlassFade)),
        findsOneWidget,
      );
      // No opacity above the glass, which would leave it reading only the
      // gallery.
      expect(
        find.ancestor(of: glass, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(
        find.ancestor(of: glass, matching: find.byType(Opacity)),
        findsNothing,
      );

      await tester.pumpAndSettle();
    });
  });
}
