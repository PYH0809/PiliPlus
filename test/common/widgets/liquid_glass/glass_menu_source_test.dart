import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/pages/setting/widgets/popup_item.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: .topCenter, child: child),
  ),
);

// The opacity the source around [finder] shows its button at.
double _shown(WidgetTester tester, Finder finder) => tester
    .widget<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-menu-source-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GlassSurfaces.install();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('a button hides while its menu is open and shows once it '
      'has returned', (tester) async {
    await tester.pumpWidget(
      _app(
        PopupMenuButton<int>(
          itemBuilder: (_) => const [PopupMenuItem(value: 1, child: Text('一'))],
          child: const Text('按钮'),
        ),
      ),
    );
    final button = find.text('按钮');
    expect(_shown(tester, button), 1);

    final gesture = await tester.startGesture(tester.getCenter(button));
    await gesture.up();
    // The snapshot is taken once the frame the menu opens on has painted.
    await tester.pump();
    await tester.pump();
    expect(find.text('一'), findsOneWidget);
    expect(_shown(tester, button), 0);

    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 500));
    await tester.pump(glassMenuReturn * 0.5);
    // Still on its way back, the menu draws the button in its droplet.
    expect(_shown(tester, button), 0);

    await tester.pumpAndSettle();
    expect(find.text('一'), findsNothing);
    expect(_shown(tester, button), 1);
  });

  testWidgets('a pull-down changes its value once the menu has landed on it', (
    tester,
  ) async {
    var value = 0;
    int? picked;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => PopupListTile<int>(
            title: const Text('语言'),
            value: () => (value, value == 0 ? '默认' : '英语'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('默认')),
              PopupMenuItem(value: 1, child: Text('英语')),
            ],
            onSelected: (newValue, refresh) {
              picked = newValue;
              setState(() => value = newValue);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();
    final current = find.text('默认').first;
    expect(_shown(tester, current), 0);

    await tester.tap(find.text('英语'));
    await tester.pump();
    await tester.pump(glassMenuReturn * 0.5);
    expect(picked, isNull);

    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.text('英语'), findsOneWidget);
    expect(_shown(tester, find.text('英语')), 1);
  });
}
