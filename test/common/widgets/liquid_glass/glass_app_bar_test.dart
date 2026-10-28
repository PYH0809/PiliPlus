import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const _width = 412.0;
const _statusBar = 24.0;

// Where content started below Material's bar, and starts under the glass one.
const _belowBar = _statusBar + kToolbarHeight;
const _barMiddle = _statusBar + kToolbarHeight / 2;

/// A settings list as the pages build theirs: in the page's own build, with
/// a context above the scaffold, and padding of its own.
Widget _list({String prefix = 'row'}) => ListView(
  padding: const EdgeInsets.only(bottom: 100),
  children: [
    const HeaderOverlaySpace(),
    for (var i = 0; i < 40; i++)
      SizedBox(key: ValueKey('$prefix$i'), height: 60),
  ],
);

Widget _settingsPage({
  bool? centerTitle,
  List<Widget>? actions,
  LiquidGlassTabBar? tabs,
  Widget? body,
}) => SimpleScaffold(
  appBar: GlassAppBar(
    title: const Text('设置'),
    centerTitle: centerTitle,
    actions: actions,
    tabs: tabs,
  ),
  body: body ?? _list(),
);

/// Pumps [page] pushed over a home route, so that it has a way back.
Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view
    ..physicalSize = const Size(_width, 800)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // As ThemeUtils sets Material's bar.
      theme: ThemeData(
        appBarTheme: const AppBarTheme(titleSpacing: 0, centerTitle: false),
      ),
      home: const Scaffold(body: Text('home')),
    ),
  );
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(MaterialPageRoute<void>(builder: (_) => page));
  await tester.pumpAndSettle();
}

double _topOf(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key))).dy;

/// The pane of glass [finder] stands on: the back button's own, or the
/// capsule the actions share, which lies beside them.
Rect _paneUnder(WidgetTester tester, Finder finder) {
  final center = tester.getCenter(finder);
  return tester
      .widgetList(find.byType(LiquidGlass))
      .map((pane) => tester.getRect(find.byWidget(pane)))
      .firstWhere((rect) => rect.contains(center));
}

void main() {
  group('glass off', () {
    setUp(() => GlassAppBar.debugEnabled = false);
    tearDown(() => GlassAppBar.debugEnabled = null);

    testWidgets('it is the Material bar it stands in for', (tester) async {
      final actions = [
        IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
        const SizedBox(width: 6),
      ];
      await _pump(tester, _settingsPage(actions: actions));

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.actions, same(actions));
      expect(appBar.centerTitle, isNull);
      expect(appBar.preferredSize, const Size.fromHeight(kToolbarHeight));
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      // Left, after the back button, as the theme has it.
      expect(tester.getTopLeft(find.text('设置')).dx, 56);
    });

    testWidgets('a capsule title is an AppBar title again', (tester) async {
      await _pump(
        tester,
        SimpleScaffold(
          appBar: const GlassAppBar(expandTitle: true, title: Text('设置')),
          body: _list(),
        ),
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).title, isA<Text>());
      expect(tester.getTopLeft(find.text('设置')).dx, 56);
    });

    testWidgets('the list starts below the bar, as before', (tester) async {
      await _pump(tester, _settingsPage());
      expect(tester.getTopLeft(find.byType(ListView)).dy, _belowBar);
      expect(_topOf(tester, 'row0'), _belowBar);
      expect(
        HeaderOverlayInset.of(
          tester.element(find.byKey(const ValueKey('row0'))),
        ),
        0,
      );
    });

    testWidgets('tabs stay out of the bar, for the page to keep its own', (
      tester,
    ) async {
      final controller = TabController(length: 2, vsync: tester);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        _settingsPage(
          tabs: LiquidGlassTabBar(
            controller: controller,
            labels: const ['视频', '专栏'],
          ),
        ),
      );
      expect(find.byType(LiquidGlassTabBar), findsNothing);
      expect(_topOf(tester, 'row0'), _belowBar);
    });

    testWidgets('GlassAppBarBody is just the body', (tester) async {
      const appBar = GlassAppBar(title: Text('日志'));
      await _pump(
        tester,
        Scaffold(
          appBar: GlassAppBar.enabled ? null : appBar,
          body: GlassAppBarBody(appBar: appBar, body: _list()),
        ),
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(_topOf(tester, 'row0'), _belowBar);
    });
  });

  group('glass on', () {
    setUp(() => GlassAppBar.debugEnabled = true);
    tearDown(() => GlassAppBar.debugEnabled = null);

    testWidgets('the list starts below the bar and scrolls under it', (
      tester,
    ) async {
      await _pump(tester, _settingsPage());
      expect(find.byType(AppBar), findsNothing);
      // The list takes the whole height, under the bar.
      expect(tester.getTopLeft(find.byType(ListView)).dy, 0);
      expect(_topOf(tester, 'row0'), _belowBar);

      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pump();
      expect(_topOf(tester, 'row0'), lessThan(_belowBar - 30));
      // The bar stays over it.
      expect(tester.getCenter(find.text('设置')).dy, _barMiddle);
    });

    testWidgets('the inset covers the status bar, which it takes away', (
      tester,
    ) async {
      await _pump(tester, _settingsPage());
      final row = tester.element(find.byKey(const ValueKey('row0')));
      // RefreshIndicator comes out from under the bar by it.
      expect(HeaderOverlayInset.of(row), _belowBar);
      expect(MediaQuery.paddingOf(row).top, 0);
    });

    testWidgets('the way back is a 44 dp circle of glass, 14 in', (
      tester,
    ) async {
      await _pump(tester, _settingsPage());
      final back = find.byTooltip('Back');
      final circle = _paneUnder(tester, back);
      expect(circle.size, const Size.square(GlassAppBar.buttonSize));
      expect(circle.left, 14);
      expect(circle.center.dy, _barMiddle);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('设置'), findsNothing);
    });

    testWidgets('the title is centered, or after the back button', (
      tester,
    ) async {
      await _pump(tester, _settingsPage());
      expect(tester.getCenter(find.text('设置')), const Offset(206, _barMiddle));

      await _pump(tester, _settingsPage(centerTitle: false));
      // After the back button, and the 8 dp its patch reaches past it.
      expect(tester.getTopLeft(find.text('设置')).dx, 14 + 44 + 16 + 8);
    });

    testWidgets('the title alone stands on a patch of the surface', (
      tester,
    ) async {
      await _pump(
        tester,
        _settingsPage(
          actions: [
            IconButton(
              tooltip: '搜索',
              onPressed: () {},
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      );
      final patch = find.ancestor(
        of: find.text('设置'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is ShapeDecoration &&
              (widget.decoration as ShapeDecoration).shadows != null,
        ),
      );
      expect(patch, findsOneWidget);
      final rect = tester.getRect(patch);
      final title = tester.getRect(find.text('设置'));
      expect(rect, title.inflate(8).intersect(rect));
      // Clear of the buttons, whose glass sees the list as the home
      // header's does.
      const reach = 16.0;
      expect(
        rect
            .inflate(reach)
            .overlaps(_paneUnder(tester, find.byTooltip('Back'))),
        isFalse,
      );
      expect(
        rect.inflate(reach).overlaps(_paneUnder(tester, find.byTooltip('搜索'))),
        isFalse,
      );
    });

    testWidgets('the actions share one capsule, without the spacers', (
      tester,
    ) async {
      await _pump(
        tester,
        _settingsPage(
          actions: [
            IconButton(
              tooltip: '搜索',
              onPressed: () {},
              icon: const Icon(Icons.search),
            ),
            TextButton(onPressed: () {}, child: const Text('保存')),
            const SizedBox(width: 12),
          ],
        ),
      );
      final capsule = _paneUnder(tester, find.byType(IconButton));
      expect(_paneUnder(tester, find.byType(TextButton)), capsule);
      expect(capsule.height, GlassAppBar.buttonSize);
      expect(capsule.right, _width - 14);
      expect(capsule.center.dy, _barMiddle);

      final search = tester.getRect(find.byType(IconButton));
      expect(search.size, const Size.square(GlassAppBar.buttonSize));
      expect(search.left, capsule.left);
      expect(tester.getRect(find.byType(TextButton)).right, capsule.right);
    });

    testWidgets('a lone action that opens a page grows it out of its circle', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(_width, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(Get.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          getPages: [
            GetPage(
              name: '/settingsSearch',
              page: () => const Scaffold(body: Text('设置搜索')),
            ),
          ],
          home: SimpleScaffold(
            appBar: GlassAppBar(
              title: const Text('设置'),
              actions: [
                GlassMorphSource(
                  builder: (context, source) => IconButton(
                    tooltip: '搜索',
                    onPressed: () => source.toNamed('/settingsSearch'),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ],
            ),
            body: _list(),
          ),
        ),
      );
      final circle = _paneUnder(tester, find.byTooltip('搜索'));
      expect(circle.size, const Size.square(GlassAppBar.buttonSize));
      final group = GlassButtonGroup.maybeOf(
        tester.element(find.byTooltip('搜索')),
      )!;
      expect(group.alone, isTrue);

      await tester.tap(find.byTooltip('搜索'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // Out of the circle, which hides whole as a GlassMorphButton does.
      expect(
        GlassMorphButton.deferUntilOpened(
          tester.element(find.text('设置搜索')),
          () {},
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(find.text('设置搜索'), findsNothing);
      expect(find.byTooltip('搜索'), findsOneWidget);
    });

    testWidgets('a capsule for a title fills the row, 8 dp from its panes', (
      tester,
    ) async {
      // As 设置's floating search.
      Widget capsule() => const SizedBox(
        key: ValueKey('capsule'),
        height: GlassAppBar.buttonSize,
        child: ColoredBox(color: Colors.grey),
      );
      await _pump(
        tester,
        SimpleScaffold(
          appBar: GlassAppBar(expandTitle: true, title: capsule()),
          body: _list(),
        ),
      );
      final back = _paneUnder(tester, find.byTooltip('Back'));
      final rect = tester.getRect(find.byKey(const ValueKey('capsule')));
      expect(rect.left, back.right + 8);
      expect(rect.right, _width - 14);
      expect(rect.height, back.height);
      expect(rect.center.dy, back.center.dy);
      // On no patch of the surface: it is a pane of its own.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('capsule')),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );

      await _pump(
        tester,
        SimpleScaffold(
          appBar: GlassAppBar(
            expandTitle: true,
            title: capsule(),
            actions: [
              IconButton(
                tooltip: '更多',
                onPressed: () {},
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
          body: _list(),
        ),
      );
      final more = _paneUnder(tester, find.byTooltip('更多'));
      expect(
        tester.getRect(find.byKey(const ValueKey('capsule'))).right,
        more.left - 8,
      );
      expect(more.right, _width - 14);
    });

    testWidgets('a capsule whose actions all hide is not drawn', (
      tester,
    ) async {
      await _pump(
        tester,
        // As a page's Obx that hides its button on another tab.
        _settingsPage(
          actions: [Builder(builder: (_) => const SizedBox.shrink())],
        ),
      );
      final panes = tester
          .widgetList(find.byType(LiquidGlass))
          .map((pane) => tester.getSize(find.byWidget(pane)))
          .toList();
      // The back circle, and the capsule, empty.
      expect(panes, [
        const Size.square(GlassAppBar.buttonSize),
        const Size(0, GlassAppBar.buttonSize),
      ]);
    });

    testWidgets('a leading of its own stands on a circle', (tester) async {
      await _pump(
        tester,
        SimpleScaffold(
          appBar: GlassAppBar(
            leading: IconButton(
              tooltip: '取消',
              onPressed: () {},
              icon: const Icon(Icons.close),
            ),
            title: const Text('已选: 2'),
          ),
          body: _list(),
        ),
      );
      expect(find.byTooltip('Back'), findsNothing);
      final circle = _paneUnder(tester, find.byTooltip('取消'));
      expect(circle.size, const Size.square(GlassAppBar.buttonSize));
      expect(circle.left, 14);
    });

    testWidgets('tabs take a second row, and the list room for both', (
      tester,
    ) async {
      final controller = TabController(length: 3, vsync: tester);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        _settingsPage(
          tabs: LiquidGlassTabBar(
            controller: controller,
            labels: const ['视频', '专栏', '合集'],
          ),
        ),
      );
      final tabs = tester.getRect(find.byType(LiquidGlassTabBar));
      expect(tabs.top, _belowBar);
      expect(tabs.height, 40);
      // A few tabs hug their labels in the middle, as the home header's.
      expect(tabs.center.dx, _width / 2);
      expect(_topOf(tester, 'row0'), _belowBar + 40 + 6);
    });

    testWidgets('a pane without a bar of its own starts below the page bar', (
      tester,
    ) async {
      // As 设置 in landscape: its list beside a page shown without its bar.
      await _pump(
        tester,
        _settingsPage(
          body: Row(
            children: [
              Expanded(child: _list()),
              Expanded(
                child: SimpleScaffold(body: _list(prefix: 'pane')),
              ),
            ],
          ),
        ),
      );
      expect(_topOf(tester, 'row0'), _belowBar);
      expect(_topOf(tester, 'pane0'), _belowBar);
    });

    testWidgets('under a Material Scaffold, through GlassAppBarBody', (
      tester,
    ) async {
      const appBar = GlassAppBar(title: Text('日志'));
      await _pump(
        tester,
        Scaffold(
          appBar: GlassAppBar.enabled ? null : appBar,
          body: GlassAppBarBody(
            appBar: appBar,
            body: CustomScrollView(
              slivers: [
                const SliverHeaderOverlaySpace(),
                SliverList.builder(
                  itemCount: 40,
                  itemBuilder: (_, i) =>
                      SizedBox(key: ValueKey('row$i'), height: 60),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(AppBar), findsNothing);
      expect(tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
      expect(_topOf(tester, 'row0'), _belowBar);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets("the status bar's icons read on the fade", (tester) async {
      await _pump(tester, _settingsPage());
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .ancestor(
              of: find.text('设置'),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value.statusBarIconBrightness, Brightness.dark);
      expect(region.value.statusBarColor, Colors.transparent);
    });
  });
}
