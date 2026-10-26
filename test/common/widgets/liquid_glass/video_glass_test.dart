import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/app_bar_ani.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/backward_seek.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
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
    Future<AnimationController> pumpBar(WidgetTester tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 300,
            child: AppBarAni(
              controller: controller,
              isTop: false,
              isFullScreen: false,
              removeSafeArea: true,
              glass: true,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: VideoGlass(
                  radius: 20,
                  child: SizedBox(height: 56),
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('turns the glass off while hidden', (tester) async {
      final controller = await pumpBar(tester);
      expect(_filters(tester), isEmpty);

      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_filters(tester), hasLength(1));

      await tester.pumpAndSettle();
      expect(_filters(tester), hasLength(1));
      expect(_filters(tester).single.$2, isFalse);
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
