import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_fab.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 400.0;
const _height = 800.0;
const _margin = kFloatingActionButtonMargin;

// The bottom end of a page, where SimpleScaffold lays a page's button, which
// keeps a margin from the edges.
Future<void> _pump(
  WidgetTester tester,
  Widget fab, {
  bool margin = true,
}) async {
  tester.view
    ..physicalSize = const Size(_width, _height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: .bottomRight,
          child: margin
              ? Padding(
                  padding: const .only(right: _margin, bottom: _margin),
                  child: fab,
                )
              : fab,
        ),
      ),
    ),
  );
}

Rect _glass(WidgetTester tester, [int index = 0]) =>
    tester.getRect(find.byType(LiquidGlass).at(index));

void main() {
  // GlassSurfaces.installed only ever turns on, so the switch is off for this
  // group and on for the next.
  group('with the switch off', () {
    testWidgets('a button is Material\'s, as before', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        GlassFab(
          tooltip: '添加',
          onPressed: () => taps++,
          child: const Icon(Icons.add),
        ),
      );
      expect(find.byType(LiquidGlass), findsNothing);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.tooltip, '添加');
      expect(tester.getSize(find.byType(GlassFab)), const Size.square(56));

      await tester.tap(find.byType(GlassFab));
      expect(taps, 1);
    });

    testWidgets('an extended button is Material\'s, as before', (
      tester,
    ) async {
      await _pump(
        tester,
        GlassFab.extended(
          onPressed: () {},
          icon: const Icon(Icons.playlist_play),
          label: const Text('播放全部'),
        ),
      );
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('播放全部'), findsOneWidget);
      expect(tester.getSize(find.byType(GlassFab)).height, 56);
    });

    testWidgets('stacked buttons are Material\'s, a margin apart, as before', (
      tester,
    ) async {
      await _pump(
        tester,
        GlassFabGroup(
          children: [
            GlassFab(onPressed: () {}, child: const Icon(Icons.swap_vert)),
            GlassFab(onPressed: () {}, child: const Icon(Icons.add)),
          ],
        ),
      );
      expect(find.byType(LiquidGlass), findsNothing);
      final fabs = find.byType(FloatingActionButton);
      expect(fabs, findsNWidgets(2));
      expect(
        tester.getRect(fabs.last).top - tester.getRect(fabs.first).bottom,
        _margin,
      );
      expect(
        tester.getRect(fabs.last).bottomRight,
        const Offset(_width - _margin, _height - _margin),
      );
    });
  });

  group('on glass', () {
    setUpAll(GlassSurfaces.install);

    testWidgets('a button is a 56 dp drop of glass, without Material\'s or '
        'its ripples', (tester) async {
      await _pump(
        tester,
        GlassFab(onPressed: () {}, child: const Icon(Icons.add)),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(_glass(tester).size, const Size.square(GlassFab.size));
      final icon = tester.widget<RichText>(
        find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
      );
      final colorScheme = Theme.of(tester.element(find.byType(GlassFab)))
          .colorScheme;
      expect(icon.text.style!.color, colorScheme.onPrimary);
    });

    testWidgets('an extended button keeps Material\'s capsule', (
      tester,
    ) async {
      Widget icon() => const Icon(Icons.sort, size: 20);
      Widget label() => const Text('最近关注');
      await _pump(
        tester,
        Row(
          mainAxisSize: .min,
          children: [
            FloatingActionButton.extended(
              onPressed: () {},
              icon: icon(),
              label: label(),
            ),
            GlassFab.extended(
              onPressed: () {},
              icon: icon(),
              label: label(),
            ),
          ],
        ),
      );
      final material = tester.getSize(find.byType(FloatingActionButton));
      expect(_glass(tester).size, material);
      expect(material.height, GlassFab.size);
    });

    testWidgets('without an icon, the label is padded 20 a side, as '
        'Material pads it', (tester) async {
      await _pump(
        tester,
        GlassFab.extended(onPressed: () {}, label: const Text('参与话题')),
      );
      final label = tester.getRect(find.text('参与话题'));
      final glass = _glass(tester);
      expect(label.left - glass.left, 20);
      expect(glass.right - label.right, 20);
    });

    testWidgets('it sits where Material\'s did, with room above for its '
        'shadow', (tester) async {
      await _pump(
        tester,
        GlassFab(onPressed: () {}, child: const Icon(Icons.add)),
      );
      final glass = _glass(tester);
      expect(
        glass.bottomRight,
        const Offset(_width - _margin, _height - _margin),
      );
      expect(
        tester.getSize(find.byType(GlassFab)).height,
        GlassFab.size + GlassFab.shadowReach,
      );
    });

    testWidgets('sliding away by its own height takes the shadow out of '
        'sight too', (tester) async {
      await _pump(
        tester,
        // As the pages slide theirs away, margin and all.
        SlideTransition(
          position: const AlwaysStoppedAnimation(Offset(0, 1)),
          child: Padding(
            padding: const .only(right: _margin, bottom: _margin),
            child: GlassFab(onPressed: () {}, child: const Icon(Icons.add)),
          ),
        ),
        margin: false,
      );
      expect(_glass(tester).top, _height + GlassFab.shadowReach);
    });

    testWidgets('stacked buttons stand on one pane, the add under the '
        'import, each pressed alone', (tester) async {
      final taps = <String>[];
      await _pump(
        tester,
        GlassFabGroup(
          children: [
            GlassFab(
              tooltip: '导入/导出',
              onPressed: () => taps.add('导入/导出'),
              child: const Icon(Icons.swap_vert, size: 26),
            ),
            GlassFab(
              tooltip: '添加',
              onPressed: () => taps.add('添加'),
              child: const Icon(Icons.add),
            ),
          ],
        ),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(LiquidGlass), findsOneWidget);
      const thickness = GlassButtonGroup.thickness;
      final pane = _glass(tester);
      expect(pane.size, const Size(thickness, thickness * 2));
      expect(
        pane.bottomRight,
        const Offset(_width - _margin, _height - _margin),
      );
      expect(
        tester.getSize(find.byType(GlassFabGroup)).height,
        thickness * 2 + GlassFab.shadowReach,
      );
      expect(
        tester.getCenter(find.byTooltip('导入/导出')).dy,
        lessThan(tester.getCenter(find.byTooltip('添加')).dy),
      );

      await tester.tap(find.byTooltip('添加'));
      await tester.tap(find.byTooltip('导入/导出'));
      expect(taps, ['添加', '导入/导出']);
    });

    testWidgets('a tap, Enter and Space press it', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        GlassFab(onPressed: () => taps++, child: const Icon(Icons.add)),
      );
      await tester.tap(find.byType(GlassFab));
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(taps, 3);
    });

    testWidgets('focused from the keyboard, it shows a ring in its '
        'content\'s color, which the tint does not swallow', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await _pump(
        tester,
        GlassFab(onPressed: () {}, child: const Icon(Icons.add)),
      );
      final ring = find.descendant(
        of: find.byType(GlassFab),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is ShapeDecoration,
        ),
      );
      expect(ring, findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final shape =
          (tester.widget<DecoratedBox>(ring).decoration as ShapeDecoration)
              .shape;
      final colorScheme = Theme.of(tester.element(find.byType(Scaffold)))
          .colorScheme;
      expect((shape as OutlinedBorder).side.color, colorScheme.onPrimary);
    });

    testWidgets('it is a button to assistive technology, named by its '
        'tooltip or its label', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Column(
          mainAxisSize: .min,
          children: [
            GlassFab(
              tooltip: '添加',
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
            GlassFab.extended(
              onPressed: () {},
              icon: const Icon(Icons.playlist_play),
              label: const Text('播放全部'),
            ),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.byType(GlassFab).first),
        isSemantics(
          label: '添加',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.byType(GlassFab).last),
        isSemantics(
          label: '播放全部',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a press swells it rather than ripple', (tester) async {
      await _pump(
        tester,
        GlassFab(onPressed: () {}, child: const Icon(Icons.add)),
      );
      final rest = _glass(tester);
      final gesture = await tester.startGesture(rest.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final pressed = _glass(tester);
      expect(pressed.width, greaterThan(rest.width));
      expect(pressed.center, rest.center);
      expect(find.byType(InkWell), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_glass(tester), rest);
    });
  });
}
