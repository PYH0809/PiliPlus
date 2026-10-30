import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/app_bar_ani.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/backward_seek.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/models/common/video_glass_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

List<T> _layers<T extends Layer>(WidgetTester tester) => [
  ...tester.layers.whereType<T>(),
];

// Each backdrop filter, and whether a translucent opacity lies above it,
// which would leave the filter reading only its own layer.
List<(BackdropFilterLayer, bool)> _filters(WidgetTester tester) {
  final found = <(BackdropFilterLayer, bool)>[];
  void walk(Layer? layer, bool faded) {
    for (; layer != null; layer = layer.nextSibling) {
      if (layer is BackdropFilterLayer) {
        found.add((layer, faded));
      }
      if (layer is ContainerLayer) {
        walk(
          layer.firstChild,
          faded || (layer is OpacityLayer && (layer.alpha ?? 255) < 255),
        );
      }
    }
  }

  walk(tester.layers.first, false);
  return found;
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: child),
  ),
);

// Notes where it lies each time it paints, as the glass in it reads it.
class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.paints, super.child});

  final List<Offset> paints;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(paints);
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this.paints);

  final List<Offset> paints;

  @override
  void paint(PaintingContext context, Offset offset) {
    paints.add(localToGlobal(Offset.zero));
    super.paint(context, offset);
  }
}

void main() {
  // VideoGlass reads whether to bend through Pref.
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-glass-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    // Frosted, so that what is counted holds whether or not the glass
    // shader has loaded, as it may have under Impeller.
    await GStorage.setting.put(
      SettingBoxKey.videoGlassMode,
      VideoGlassMode.frost.index,
    );
  });
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('filters the screen while shown', (tester) async {
    await tester.pumpWidget(
      _app(const VideoGlass.capsule(child: SizedBox(width: 120, height: 36))),
    );
    expect(_filters(tester), hasLength(1));
  });

  testWidgets('filters nothing at t 0 or while hidden', (tester) async {
    await tester.pumpWidget(
      _app(
        const VideoGlass(
          radius: 20,
          t: 0,
          child: SizedBox(width: 120, height: 36),
        ),
      ),
    );
    expect(_filters(tester), isEmpty);

    await tester.pumpWidget(
      _app(
        const VideoGlassHidden(
          hidden: true,
          child: VideoGlass.capsule(child: SizedBox(width: 120, height: 36)),
        ),
      ),
    );
    expect(_filters(tester), isEmpty);
  });

  testWidgets('panes of a group read one backdrop', (tester) async {
    final group = BackdropGroup(
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoGlass.capsule(child: SizedBox(width: 120, height: 36)),
          SizedBox(height: 8),
          VideoGlass(radius: 20, child: SizedBox(width: 200, height: 60)),
        ],
      ),
    );
    await tester.pumpWidget(_app(group));
    final keys = {
      for (final (layer, _) in _filters(tester)) layer.backdropKey,
    };
    expect(_filters(tester), hasLength(2));
    expect(keys, {group.backdropKey});
  });

  testWidgets('a pane easing in keeps out of its group', (tester) async {
    final group = BackdropGroup(
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoGlass.capsule(child: SizedBox(width: 120, height: 36)),
          SizedBox(height: 8),
          VideoGlass(
            radius: 20,
            t: 0.5,
            child: SizedBox(width: 200, height: 60),
          ),
        ],
      ),
    );
    await tester.pumpWidget(_app(group));
    final keys = [for (final (layer, _) in _filters(tester)) layer.backdropKey];
    expect(keys, [group.backdropKey, null]);
  });

  testWidgets('clips the filter to the pane, but not the child', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const VideoGlass.capsule(child: SizedBox(width: 120, height: 36))),
    );
    final clip = _layers<ClipRSuperellipseLayer>(tester).single;
    // A progress bar's thumb glows past the pane, so the child is painted
    // after the clip, not in it.
    expect(clip.firstChild, isA<BackdropFilterLayer>());
    expect(clip.firstChild, same(clip.lastChild));
  });

  testWidgets('the button style keeps focus and activation', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        FilledButton(
          style: VideoGlass.buttonStyle(),
          onPressed: () => pressed++,
          child: const Text('还原屏幕'),
        ),
      ),
    );
    expect(_filters(tester), hasLength(1));
    await tester.tap(find.text('还原屏幕'));
    expect(pressed, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressed, 2);
  });

  testWidgets('the controls theme is dark without ripples', (tester) async {
    final light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    final theme = VideoGlass.controlsTheme(light);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.splashFactory, NoSplash.splashFactory);
    // A menu item without a color of its own reads light on the glass.
    expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
    expect(theme.textTheme.labelLarge?.color, theme.colorScheme.onSurface);
    expect(theme.iconTheme.color, theme.colorScheme.onSurfaceVariant);
  });

  group('AppBarAni on glass', () {
    final video = GlobalKey();

    Future<AnimationController> pumpBar(
      WidgetTester tester, {
      bool glass = true,
      bool overVideo = false,
      List<Offset>? paints,
    }) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      Widget pane = Padding(
        padding: const EdgeInsets.all(8),
        child: VideoGlass(
          radius: 20,
          child: Semantics(
            container: true,
            label: 'bar',
            child: const SizedBox(height: 56),
          ),
        ),
      );
      if (paints != null) {
        pane = _PaintProbe(paints: paints, child: pane);
      }
      Widget bar = AppBarAni(
        controller: controller,
        isTop: false,
        isFullScreen: false,
        removeSafeArea: true,
        glass: glass,
        child: pane,
      );
      if (overVideo) {
        // As in the player, the pane draws the video again.
        bar = VideoGlassSource(
          video: video,
          child: SizedBox(
            height: 200,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    key: video,
                    child: const Texture(textureId: 7),
                  ),
                ),
                Positioned(left: 0, right: 0, bottom: 0, child: bar),
              ],
            ),
          ),
        );
      }
      await tester.pumpWidget(_app(SizedBox(width: 300, child: bar)));
      return controller;
    }

    // The video's own texture, and the pane's copy of it while it draws live.
    int textures(WidgetTester tester) => _layers<TextureLayer>(tester).length;

    testWidgets('turns the glass off while hidden', (tester) async {
      final controller = await pumpBar(tester);
      expect(_filters(tester), isEmpty);

      controller.forward();
      await tester.pumpAndSettle();
      expect(_filters(tester), hasLength(1));
      expect(_filters(tester).single.$2, isFalse);

      controller.reverse();
      await tester.pumpAndSettle();
      expect(_filters(tester), isEmpty);
    });

    testWidgets('slides in from a snapshot of the bar at rest', (
      tester,
    ) async {
      final paints = <Offset>[];
      final controller = await pumpBar(
        tester,
        overVideo: true,
        paints: paints,
      );
      paints.clear();

      controller.forward();
      await tester.pump();
      // Setting off out of sight, the bar is taken where it comes to rest.
      expect(textures(tester), 1);
      expect(paints, hasLength(1));
      final rest = paints.single;

      await tester.pump(const Duration(milliseconds: 50));
      // Moving, it is the snapshot, not the glass drawn again.
      expect(textures(tester), 1);
      expect(paints, hasLength(1));
      // Where it is drawn, as taps find it.
      expect(
        tester.getTopLeft(find.byType(VideoGlass)).dy,
        greaterThan(rest.dy),
      );

      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.isCompleted, isTrue);
      // The frame it lands in still moves it: the snapshot.
      expect(textures(tester), 1);
      expect(paints, hasLength(1));

      await tester.pump();
      expect(textures(tester), 2);
      expect(paints, [rest, rest]);
    });

    testWidgets('slides out from a snapshot of the bar as it stands', (
      tester,
    ) async {
      final paints = <Offset>[];
      final controller = await pumpBar(
        tester,
        overVideo: true,
        paints: paints,
      );
      controller.value = 1;
      await tester.pump();
      expect(textures(tester), 2);
      final rest = paints.last;
      paints.clear();

      controller.reverse();
      await tester.pump();
      expect(textures(tester), 1);
      expect(paints, [rest]);

      await tester.pump(const Duration(milliseconds: 50));
      expect(textures(tester), 1);
      expect(paints, [rest]);

      // Out of sight, drawn live with the glass off.
      await tester.pumpAndSettle();
      expect(controller.isDismissed, isTrue);
      expect(textures(tester), 1);
      expect(paints, hasLength(2));
    });

    testWidgets('tells assistive technology where the bar slides', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = await pumpBar(tester, overVideo: true);
      // The pane's rect on screen, as a screen reader outlines it.
      Rect outline() {
        final node = tester.getSemantics(find.bySemanticsLabel('bar'));
        var rect = node.rect;
        for (SemanticsNode? n = node; n != null; n = n.parent) {
          if (n.transform case final transform?) {
            rect = MatrixUtils.transformRect(transform, rect);
          }
        }
        // The root's transform takes it to physical pixels.
        return rect.topLeft / tester.view.devicePixelRatio &
            rect.size / tester.view.devicePixelRatio;
      }

      controller.value = 1;
      await tester.pump();
      final rest = outline();

      controller.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        outline().top,
        closeTo(tester.getTopLeft(find.byType(VideoGlass)).dy, 0.01),
      );
      expect(outline().top, greaterThan(rest.top));
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('without glass the bar slides as before', (tester) async {
      final paints = <Offset>[];
      final controller = await pumpBar(tester, glass: false, paints: paints);
      expect(
        find.descendant(
          of: find.byType(AppBarAni),
          matching: find.byType(SlideTransition),
        ),
        findsOneWidget,
      );
      paints.clear();

      // Drawn again at each step.
      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));
      expect(paints, hasLength(2));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps taps between the panes from the player', (
      tester,
    ) async {
      final controller = await pumpBar(tester);
      controller.value = 1;
      await tester.pump();
      final box = tester.renderObject<RenderBox>(find.byType(AppBarAni));
      final result = BoxHitTestResult();
      // The corner of the bar, outside its pane.
      box.hitTest(result, position: const Offset(2, 2));
      expect(
        result.path.any((entry) => entry.target is RenderDecoratedBox),
        isTrue,
      );
    });
  });

  testWidgets('a seek note eases in on glass without fading the filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 200,
          height: 200,
          child: BackwardSeekIndicator(
            glassT: 0.5,
            duration: const Duration(seconds: 10),
            onSubmitted: (_) {},
          ),
        ),
      ),
    );
    final filters = _filters(tester);
    expect(filters, hasLength(1));
    expect(filters.single.$2, isFalse);
    expect(find.text('快退10秒'), findsOneWidget);
    // Let the indicator's submit timer run out.
    await tester.pump(const Duration(milliseconds: 500));
  });
}
