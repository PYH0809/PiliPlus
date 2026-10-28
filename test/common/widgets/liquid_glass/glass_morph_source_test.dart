import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    GetMaterialApp(
      // As main.dart's builder.
      builder: (context, child) => LiquidGlassScope(
        enabled: true,
        child: LiquidGlassHost(enabled: true, child: child!),
      ),
      getPages: [
        GetPage(
          name: '/search',
          page: () => const Scaffold(body: Center(child: Text('搜索页'))),
        ),
      ],
      home: Scaffold(body: Center(child: home)),
    ),
  );
}

GlassMorphSource _search() => GlassMorphSource(
  builder: (context, source) => IconButton(
    tooltip: '搜索',
    onPressed: () => source.toNamed('/search'),
    icon: const Icon(Icons.search),
  ),
);

/// Whether the page shown is still growing out of a glass button.
bool _morphing(WidgetTester tester) => GlassMorphButton.deferUntilOpened(
  tester.element(find.text('搜索页')),
  () {},
);

// The page below stays in the tree, offstage, under the one it opened.
Finder _offstage(Finder finder) =>
    find.byElementPredicate((e) => finder.evaluate().contains(e));

double _opacityAbove(WidgetTester tester, Finder child) => tester
    .widget<Opacity>(
      find.ancestor(of: child, matching: find.byType(Opacity)).first,
    )
    .opacity;

/// Counts its paints, repainting whenever [repaint] changes.
class _CountingPainter extends CustomPainter {
  _CountingPainter(this.repaint, this.onPaint) : super(repaint: repaint);

  final Listenable repaint;
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

void main() {
  tearDown(Get.reset);

  testWidgets('the page under a morph is drawn from a picture of it', (
    tester,
  ) async {
    var paints = 0;
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size.square(40),
            painter: _CountingPainter(changes, () => paints++),
          ),
          GlassButtonGroup(glass: true, children: [_search()]),
        ],
      ),
    );
    Future<bool> repaintsBelow() async {
      final before = paints;
      changes.value++;
      await tester.pump(const Duration(milliseconds: 16));
      return paints > before;
    }

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    // The button hides a frame on, and the page is taken the frame after.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_morphing(tester), isTrue);
    expect(await repaintsBelow(), isFalse);

    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('搜索页'), findsOneWidget);
    expect(await repaintsBelow(), isFalse);

    await tester.pumpAndSettle();
    expect(find.text('搜索页'), findsNothing);
    expect(await repaintsBelow(), isTrue);
  });

  testWidgets('the page under a morph shows itself once the screen changes', (
    tester,
  ) async {
    var paints = 0;
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size.square(40),
            painter: _CountingPainter(changes, () => paints++),
          ),
          GlassButtonGroup(glass: true, children: [_search()]),
        ],
      ),
    );
    Future<bool> repaintsBelow() async {
      final before = paints;
      changes.value++;
      await tester.pump(const Duration(milliseconds: 16));
      return paints > before;
    }

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(await repaintsBelow(), isFalse);

    // As a screen turning: the picture no longer fits, so the page draws.
    tester.view.physicalSize = tester.view.physicalSize.flipped;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_morphing(tester), isTrue);
    expect(await repaintsBelow(), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets("a grouped button's page grows out of it, the pane staying", (
    tester,
  ) async {
    await _pump(
      tester,
      GlassButtonGroup(
        glass: true,
        children: [
          _search(),
          IconButton(
            tooltip: '更多',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('搜索页'), findsOneWidget);
    expect(_morphing(tester), isTrue);

    final search = find.byTooltip('搜索', skipOffstage: false);
    final pane = find.byType(LiquidGlass, skipOffstage: false).first;
    // Only the button's face hides, under the page; the pane stays.
    expect(_opacityAbove(tester, _offstage(search)), 0);
    expect(_opacityAbove(tester, _offstage(pane)), 1);

    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('搜索页'), findsNothing);
    expect(_opacityAbove(tester, find.byTooltip('搜索')), 1);
  });

  testWidgets('alone in its group, it hides the whole group', (tester) async {
    await _pump(tester, GlassButtonGroup(glass: true, children: [_search()]));
    final group = GlassButtonGroup.maybeOf(
      tester.element(find.byTooltip('搜索')),
    )!;
    final groupBox = group.box!;

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_morphing(tester), isTrue);
    // The whole pane, as a GlassMorphButton hides.
    final pane = find.byType(LiquidGlass, skipOffstage: false).first;
    expect(_opacityAbove(tester, _offstage(pane)), 0);
    expect(groupBox.attached, isTrue);

    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(_opacityAbove(tester, find.byType(LiquidGlass).first), 1);
    // It was hidden, not built again.
    expect(
      GlassButtonGroup.maybeOf(tester.element(find.byTooltip('搜索'))),
      same(group),
    );
  });

  testWidgets('off glass it opens the page as Get.toNamed does', (
    tester,
  ) async {
    await _pump(tester, GlassButtonGroup(glass: false, children: [_search()]));
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('搜索页'), findsOneWidget);
    expect(_morphing(tester), isFalse);
    expect(
      _opacityAbove(
        tester,
        _offstage(find.byTooltip('搜索', skipOffstage: false)),
      ),
      1,
    );
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/search');
  });

  testWidgets("the button's face in the page takes no keyboard focus", (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        builder: (context, child) => LiquidGlassScope(
          enabled: true,
          child: LiquidGlassHost(enabled: true, child: child!),
        ),
        getPages: [
          GetPage(
            name: '/search',
            page: () => Scaffold(
              body: Center(
                child: TextButton(onPressed: () {}, child: const Text('页内按钮')),
              ),
            ),
          ),
        ],
        home: Scaffold(
          body: Center(
            child: GlassButtonGroup(
              glass: true,
              children: [
                GlassMorphSource(
                  builder: (context, source) => IconButton(
                    tooltip: '搜索',
                    onPressed: () {
                      presses++;
                      source.toNamed('/search');
                    },
                    icon: const Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('页内按钮'), findsOneWidget);

    // Tab goes round the page's own button alone, never the face drawn in it.
    final faces = find.byTooltip('搜索', skipOffstage: false);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == focused),
          matching: faces,
        ),
        findsNothing,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('a lone button whose group grows under its page shows again', (
    tester,
  ) async {
    final more = ValueNotifier(false);
    addTearDown(more.dispose);
    await _pump(
      tester,
      ValueListenableBuilder(
        valueListenable: more,
        builder: (_, more, _) => GlassButtonGroup(
          glass: true,
          children: [
            _search(),
            if (more)
              IconButton(
                tooltip: '更多',
                onPressed: () {},
                icon: const Icon(Icons.more_vert),
              ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    // Alone, it hid the whole group; then the group gains a button.
    more.value = true;
    await tester.pump();

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(_opacityAbove(tester, find.byType(LiquidGlass).first), 1);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('搜索页'), findsOneWidget);
  });

  testWidgets('a group its lone button leaves under its page shows again', (
    tester,
  ) async {
    final gone = ValueNotifier(false);
    addTearDown(gone.dispose);
    await _pump(
      tester,
      ValueListenableBuilder(
        valueListenable: gone,
        builder: (_, gone, _) => GlassButtonGroup(
          glass: true,
          children: [
            if (gone)
              IconButton(
                tooltip: '更多',
                onPressed: () {},
                icon: const Icon(Icons.more_vert),
              )
            else
              _search(),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    gone.value = true;
    await tester.pump();
    await tester.pump();

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(_opacityAbove(tester, find.byType(LiquidGlass).first), 1);
    expect(find.byTooltip('更多'), findsOneWidget);
  });

  testWidgets('a page outlives the button it grew out of', (tester) async {
    // As 设置 turning to landscape under its open search: the button is
    // built again elsewhere.
    final moved = ValueNotifier(false);
    addTearDown(moved.dispose);
    await _pump(
      tester,
      ValueListenableBuilder(
        valueListenable: moved,
        builder: (_, moved, _) {
          final group = GlassButtonGroup(glass: true, children: [_search()]);
          return moved ? Padding(padding: .zero, child: group) : group;
        },
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    moved.value = true;
    await tester.pump();

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('搜索页'), findsNothing);
    expect(_opacityAbove(tester, find.byType(LiquidGlass).first), 1);
  });

  testWidgets('a keyed GlassMorphButton moved under its page keeps it', (
    tester,
  ) async {
    // As 设置's search, between the bar and the landscape list pane's.
    final key = GlobalKey<GlassMorphButtonState>();
    final moved = ValueNotifier(false);
    addTearDown(moved.dispose);
    Widget button() => SizedBox.square(
      dimension: 40,
      child: GlassMorphButton(
        key: key,
        tooltip: '搜索',
        onTap: (button) => button.toNamed('/search'),
        child: const Icon(Icons.search),
      ),
    );
    await _pump(
      tester,
      ValueListenableBuilder(
        valueListenable: moved,
        builder: (_, moved, _) => moved
            ? Align(alignment: Alignment.topLeft, child: button())
            : button(),
      ),
    );
    final state = key.currentState;
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    moved.value = true;
    await tester.pump();
    // The same button, still hidden under its page, where it stands now.
    expect(key.currentState, same(state));
    expect(
      tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byKey(key, skipOffstage: false),
                  matching: find.byType(Opacity, skipOffstage: false),
                )
                .first,
          )
          .opacity,
      0,
    );

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_opacityAbove(tester, find.byType(LiquidGlass).first), 1);
    expect(tester.getTopLeft(find.byTooltip('搜索')), Offset.zero);
  });

  testWidgets('the face of a button scaled down is drawn at its size', (
    tester,
  ) async {
    // As 我的's header, scaled down to fit beside the player bar.
    await _pump(
      tester,
      Transform.scale(
        scale: 0.8,
        child: GlassButtonGroup(glass: true, children: [_search()]),
      ),
    );
    final button = tester.getRect(find.byTooltip('搜索'));
    expect(button.width, closeTo(GlassButtonGroup.thickness * 0.8, 0.01));

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    for (final ms in [16, 100, 200]) {
      await tester.pump(Duration(milliseconds: ms));
      // Every copy of it, the face drawn in the morph too, as big as the
      // button stands on screen.
      final copies = find.byTooltip('搜索', skipOffstage: false).evaluate();
      expect(copies.length, 2);
      for (final copy in copies) {
        final box = copy.renderObject! as RenderBox;
        final rect = MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
        expect(rect.width, closeTo(button.width, 0.01));
        expect(rect.height, closeTo(button.height, 0.01));
      }
    }
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("the face in the morph wears its button's themes", (
    tester,
  ) async {
    // A local theme above the button, as a header tints its icons.
    await _pump(
      tester,
      Theme(
        data: ThemeData(iconTheme: const IconThemeData(color: Colors.pink)),
        child: GlassButtonGroup(
          glass: true,
          children: [
            GlassMorphSource(
              builder: (context, source) => IconButton(
                tooltip: '搜索',
                color: IconTheme.of(context).color,
                onPressed: () => source.toNamed('/search'),
                icon: const Icon(Icons.search),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final copies = find.byTooltip('搜索', skipOffstage: false).evaluate();
    expect(copies.length, 2);
    for (final copy in copies) {
      expect(IconTheme.of(copy).color, Colors.pink);
      // Sized by the group's theme, as the button is.
      expect(copy.size, const Size.square(GlassButtonGroup.thickness));
    }
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
  });

  testWidgets('a GlassMorphButton still opens its page out of itself', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox.square(
        dimension: 40,
        child: GlassMorphButton(
          tooltip: '搜索',
          onTap: (button) => button.toNamed('/search'),
          child: const Icon(Icons.search),
        ),
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_morphing(tester), isTrue);
    expect(
      _opacityAbove(
        tester,
        _offstage(find.byType(LiquidGlass, skipOffstage: false).first),
      ),
      0,
    );

    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('搜索页'), findsNothing);
    expect(_opacityAbove(tester, find.byType(LiquidGlass).first), 1);
  });
}
