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

void main() {
  tearDown(Get.reset);

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
