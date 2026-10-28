import 'dart:io';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/pages/mine/widgets/glass_header.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _side = GlassButtonGroup.thickness;
const _extent = 6 + _side + 4;

/// The page's list, as the mine page lays it out: starting below the header,
/// with room at the end for the navigation bar.
class _List extends StatelessWidget {
  const _List({this.onTap});

  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return refreshIndicator(
      onRefresh: () => Future.delayed(const Duration(seconds: 1)),
      child: ListView(
        padding: .only(top: HeaderOverlayInset.of(context), bottom: 150),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 20; i++)
            GestureDetector(
              behavior: .opaque,
              onTap: () => onTap?.call(i),
              child: SizedBox(key: ValueKey('item$i'), height: 80),
            ),
        ],
      ),
    );
  }
}

/// The header's buttons, as the mine page's: with the padding and icon size
/// they have without glass.
List<Widget> _actions(int count) => [
  for (var i = 0; i < count; i++)
    IconButton(
      iconSize: 22,
      padding: const EdgeInsets.all(8),
      style: const ButtonStyle(tapTargetSize: .shrinkWrap),
      tooltip: 'a$i',
      onPressed: () {},
      icon: const Icon(Icons.settings_outlined),
    ),
];

Finder _actionGroup() => find.ancestor(
  of: find.byTooltip('a0'),
  matching: find.byType(GlassButtonGroup),
);

Future<void> _pump(
  WidgetTester tester, {
  int actions = 4,
  bool showBackBtn = false,
  double width = 412,
  ValueChanged<int>? onTap,
}) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MineGlassBody(
          showBackBtn: showBackBtn,
          actions: _actions(actions),
          content: _List(onTap: onTap),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  // The refresh indicator reads its displacement from the settings, and the
  // groups stand on glass once it is installed, as main() does with the
  // switch on.
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-mine-header-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GlassSurfaces.install();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('the buttons share one pane of glass, 14 in from the end', (
    tester,
  ) async {
    await _pump(tester);
    final group = _actionGroup();
    expect(group, findsOneWidget);
    expect(
      find.descendant(of: group, matching: find.byType(LiquidGlass)),
      findsOneWidget,
    );
    expect(
      tester.getRect(group),
      const Rect.fromLTRB(412 - 14 - 4 * _side, 6, 412 - 14, 6 + _side),
    );
    // Side by side, each as tall as the pane, without gaps.
    for (var i = 0; i < 4; i++) {
      expect(
        tester.getRect(find.byTooltip('a$i')),
        Rect.fromLTWH(412 - 14 - (4 - i) * _side, 6, _side, _side),
      );
    }
  });

  testWidgets('the list starts below the header and scrolls under it', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('item0'))).dy, _extent);
    await tester.drag(find.byType(ListView), const Offset(0, -30));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('item0'))).dy,
      lessThan(_extent),
    );
    // Still under the header's buttons, which stay put.
    expect(tester.getRect(_actionGroup()).top, 6);
  });

  testWidgets('a refresh comes out from under the header', (tester) async {
    await _pump(tester);
    expect(
      HeaderOverlayInset.of(tester.element(find.byType(ListView))),
      _extent,
    );
    final gesture = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    final indicator = find.byType(RefreshProgressIndicator);
    expect(indicator, findsOneWidget);
    expect(tester.getRect(indicator).top, greaterThanOrEqualTo(_extent));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the last item clears a bar along the bottom', (tester) async {
    await _pump(tester);
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('item19'))).dy,
      800 - 150,
    );
  });

  testWidgets('touches beside the buttons and on the fade reach the list', (
    tester,
  ) async {
    int? tapped;
    await _pump(tester, onTap: (i) => tapped = i);
    // Left of the buttons, and in the fade below them.
    await tester.tapAt(const Offset(60, _extent + 6));
    expect(tapped, 0);
  });

  testWidgets('in the tab, no back button', (tester) async {
    await _pump(tester);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(GlassButtonGroup), findsOneWidget);
  });

  testWidgets('opened as a page, the back button stands on a circle of its '
      'own, 14 in, and pops it', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Material(
          child: MineGlassBody(
            showBackBtn: true,
            actions: _actions(5),
            content: const _List(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final back = find.byType(BackButton);
    expect(back, findsOneWidget);
    final group = find.ancestor(
      of: back,
      matching: find.byType(GlassButtonGroup),
    );
    expect(tester.getRect(group), const Rect.fromLTWH(14, 6, _side, _side));
    // Apart from the others' pane.
    expect(
      find.descendant(of: group, matching: find.byTooltip('a0')),
      findsNothing,
    );
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(MineGlassBody), findsNothing);
  });

  testWidgets('a narrow window shrinks the buttons to fit', (tester) async {
    await _pump(tester, actions: 7, showBackBtn: true, width: 320);
    expect(tester.takeException(), isNull);
    for (final finder in [
      find.byType(BackButton),
      for (var i = 0; i < 7; i++) find.byTooltip('a$i'),
    ]) {
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('设置 opens out of its button on the pane and returns into it, '
      'scaled down too', (tester) async {
    for (final width in [412.0, 320.0]) {
      tester.view
        ..physicalSize = Size(width, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          // As main.dart's builder.
          builder: (context, child) => LiquidGlassScope(
            enabled: true,
            child: LiquidGlassHost(enabled: true, child: child!),
          ),
          getPages: [
            GetPage(
              name: '/setting',
              page: () => const Scaffold(body: Center(child: Text('设置页'))),
            ),
          ],
          home: Scaffold(
            body: MineGlassBody(
              showBackBtn: true,
              actions: [
                ..._actions(6),
                GlassMorphSource(
                  builder: (context, source) => IconButton(
                    tooltip: '设置',
                    onPressed: () => source.toNamed('/setting'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ),
              ],
              content: const _List(),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('设置页'), findsOneWidget);
      expect(
        GlassMorphButton.deferUntilOpened(
          tester.element(find.text('设置页')),
          () {},
        ),
        isTrue,
        reason: 'growing out of the button at $width',
      );
      await tester.pumpAndSettle();
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('设置页'), findsNothing);
      // Back in its place, shown again.
      final shown = tester.widget<Opacity>(
        find
            .ancestor(of: find.byTooltip('设置'), matching: find.byType(Opacity))
            .first,
      );
      expect(shown.opacity, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
    }
  });

  testWidgets('消息 going while its page is open or returning, as it does '
      'logged out, breaks nothing', (tester) async {
    for (final returning in [false, true]) {
      final shown = ValueNotifier(true);
      await tester.pumpWidget(
        GetMaterialApp(
          // As main.dart's builder.
          builder: (context, child) => LiquidGlassScope(
            enabled: true,
            child: LiquidGlassHost(enabled: true, child: child!),
          ),
          getPages: [
            GetPage(
              name: '/whisper',
              page: () => const Scaffold(body: Center(child: Text('消息页'))),
            ),
          ],
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: shown,
              builder: (context, value, _) => MineGlassBody(
                actions: [
                  // As msgBadge hides it logged out.
                  if (value)
                    GlassMorphSource(
                      builder: (context, source) => IconButton(
                        tooltip: '消息',
                        onPressed: () => source.toNamed('/whisper'),
                        icon: const Icon(Icons.notifications_none),
                      ),
                    ),
                  ..._actions(2),
                ],
                content: const _List(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('消息'));
      await tester.pumpAndSettle();
      expect(find.text('消息页'), findsOneWidget);
      if (!returning) {
        shown.value = false;
        await tester.pump();
      }
      Get.back<void>();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      if (returning) {
        shown.value = false;
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('消息页'), findsNothing);
      expect(find.byTooltip('消息'), findsNothing);
      expect(find.byTooltip('a0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      shown.dispose();
      Get.reset();
    }
  });
}
