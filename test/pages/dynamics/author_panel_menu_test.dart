import 'dart:io';

import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/widgets/author_panel.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

DynamicItemModel _item() => DynamicItemModel.fromJson({
  'id_str': '1',
  'type': 'DYNAMIC_TYPE_WORD',
  'basic': {'comment_id_str': '1', 'comment_type': 17},
  'modules': {
    'module_author': {
      'mid': 2,
      'name': 'HOMOLAB',
      'pub_time': '9小时前',
      'type': 'AUTHOR_TYPE_NORMAL',
    },
    'module_dynamic': {
      'desc': {'text': '一条动态'},
    },
  },
});

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: .topCenter, child: child),
  ),
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-author-panel-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  // A phone's height, so that the menu fits below where it opens.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(412, 915);
    view.devicePixelRatio = 1;
  });

  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio(),
  );

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('the more button opens a menu under it, not a sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(AuthorPanel(item: _item())));

    final button = tester.getRect(find.byTooltip('更多'));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('分享动态'), findsOneWidget);
    expect(find.text('临时屏蔽：HOMOLAB'), findsOneWidget);
    // A popover dismisses by a tap outside; it has no 取消 row.
    expect(find.text('取消'), findsNothing);
    expect(
      tester.getRect(find.text('保存动态')).top,
      greaterThanOrEqualTo(button.bottom),
    );

    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();
    expect(find.text('分享动态'), findsNothing);
  });

  testWidgets('a long press opens the menu where the finger is', (
    tester,
  ) async {
    final panel = AuthorPanel(item: _item());
    const at = Offset(200, 100);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => panel.showMoreMenu(context, at),
            child: const Text('card'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final first = tester.getRect(find.text('保存动态'));
    expect(first.top, greaterThanOrEqualTo(at.dy));
    expect(first.top, lessThan(at.dy + 60));
  });
}
