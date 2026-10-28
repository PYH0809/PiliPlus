import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/pages/member/widget/member_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void _size(WidgetTester tester, {double width = 412}) {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The space page's bar over a page that can go back to a first one.
Future<List<String>> _pumpBar(WidgetTester tester) async {
  _size(tester);
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      // As the app's theme.
      theme: ThemeData(appBarTheme: const AppBarTheme(titleSpacing: 0)),
      // As main.dart's builder, so that the panes bend what is under them.
      builder: (context, child) => LiquidGlassScope(
        enabled: true,
        child: LiquidGlassHost(enabled: true, child: child!),
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  leading: MemberGlassBar.leading(context),
                  leadingWidth: MemberGlassBar.leadingWidth,
                  title: const Text('UP'),
                  // As the page's own: a search, a menu and a gap at the end.
                  actions: MemberGlassBar.actions([
                    IconButton(
                      tooltip: '搜索',
                      onPressed: () => taps.add('搜索'),
                      icon: const Icon(Icons.search_outlined),
                    ),
                    PopupMenuButton(
                      tooltip: '更多',
                      icon: const Icon(Icons.more_vert),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          onTap: () => taps.add('分享'),
                          child: const Text('分享UP主'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ]),
                ),
              ),
            ),
          ),
          child: const Text('first'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('first'));
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  // The capsule and menus on glass, as main() installs them with the switch
  // on.
  setUpAll(GlassSurfaces.install);

  testWidgets('the back circle and the capsule stand 14 in from the sides', (
    tester,
  ) async {
    await _pumpBar(tester);
    const side = GlassButtonGroup.thickness;
    final back = tester.getRect(find.byType(MemberGlassBackButton));
    expect(back.size, const Size(side, side));
    expect(back.left, 14);
    final capsule = tester.getRect(find.byType(GlassButtonGroup));
    expect(capsule.height, side);
    expect(capsule.right, 412 - 14);
    expect(capsule.center.dy, back.center.dy);
    // Side by side on one pane, without the gap the page kept at the end.
    final search = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.search_outlined),
    );
    final more = tester.getRect(find.byType(PopupMenuButton));
    expect(search.left, capsule.left);
    expect(more.left, search.right);
    expect(more.right, capsule.right);
    expect(
      find.descendant(
        of: find.byType(GlassButtonGroup),
        matching: find.byType(LiquidGlass),
      ),
      findsOneWidget,
    );
    // The title follows the back button as it follows the bar's others.
    expect(tester.getTopLeft(find.text('UP')).dx, 14 + side + 12);
  });

  testWidgets('the back circle goes back', (tester) async {
    await _pumpBar(tester);
    await tester.tap(find.byType(MemberGlassBackButton));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.byType(MemberGlassBackButton), findsNothing);
  });

  testWidgets('no back circle where the page cannot go back', (tester) async {
    _size(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(leading: MemberGlassBar.leading(context)),
          ),
        ),
      ),
    );
    expect(find.byType(MemberGlassBackButton), findsNothing);
  });

  testWidgets('the capsule\'s buttons keep their own taps and menus', (
    tester,
  ) async {
    final taps = await _pumpBar(tester);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享UP主'));
    await tester.pumpAndSettle();
    expect(taps, ['搜索', '分享']);
  });
}
