import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
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
