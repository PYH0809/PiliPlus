import 'package:PiliPlus/pages/video/widgets/settings_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final taps = <String>[];

  ListTile row(String title) => ListTile(
    dense: true,
    title: Text(title),
    onTap: () => taps.add(title),
  );

  Future<void> pump(WidgetTester tester, {bool disableAnimations = false}) {
    taps.clear();
    return tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 400,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 560),
                    child: GroupedSettings(
                      children: [
                        row('添加至「稍后再看」'),
                        row('查看笔记'),
                        row('离线缓存'),
                        row('定时关闭'),
                        row('超分辨率'),
                        row('选择画质'),
                        row('播放顺序'),
                        row('重载视频'),
                        row('上游新加的一行'),
                        SettingsEntry(
                          group: SettingsGroup.sound,
                          order: 1,
                          child: Builder(builder: (context) => row('播放器音量')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(GroupedSettings)).height;

  testWidgets('rows go where their titles say, the rest to 更多', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    // The first level: its own rows, in their order, then a row a group.
    for (final title in ['添加至「稍后再看」', '离线缓存', '定时关闭', '播放顺序']) {
      expect(find.text(title), findsOneWidget);
    }
    for (final title in ['查看笔记', '超分辨率', '重载视频', '上游新加的一行']) {
      expect(find.text(title), findsNothing);
    }
    for (final group in ['画面', '声音', '播放问题', '更多']) {
      expect(find.text(group), findsOneWidget);
    }
    // No row of its own, no row for it.
    expect(find.text('弹幕和字幕'), findsNothing);
    final top = tester.getTopLeft(find.text('离线缓存')).dy;
    expect(tester.getTopLeft(find.text('定时关闭')).dy, greaterThan(top));

    await tester.tap(find.text('画面'));
    await tester.pumpAndSettle();
    // In 画面, ordered: 选择画质 first, though given after 超分辨率.
    expect(
      tester.getTopLeft(find.text('选择画质')).dy,
      lessThan(tester.getTopLeft(find.text('超分辨率')).dy),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('查看笔记'), findsOneWidget);
    // A row no title names lands here, after those that are.
    expect(find.text('上游新加的一行'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('上游新加的一行')).dy,
      greaterThan(tester.getTopLeft(find.text('查看笔记')).dy),
    );
  });

  testWidgets('a group opens in place and its rows do as they did', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    final topHeight = sheetHeight(tester);

    await tester.tap(find.text('声音'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Midway, both levels stand side by side, the first slid aside.
    expect(find.text('播放器音量'), findsOneWidget);
    await tester.pumpAndSettle();
    // The sheet as tall as the group, a header and one row.
    expect(sheetHeight(tester), lessThan(topHeight));

    await tester.tap(find.text('播放器音量'));
    expect(taps, ['播放器音量']);

    // Its header goes back, the sheet tall again.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('播放器音量'), findsNothing);
    expect(sheetHeight(tester), topHeight);
    await tester.tap(find.text('定时关闭'));
    expect(taps, ['播放器音量', '定时关闭']);
  });

  testWidgets('under a group the first level takes no focus', (tester) async {
    await pump(tester);
    await tester.pump();
    bool excluded() => tester
        .widget<ExcludeFocus>(
          find.ancestor(
            of: find.text('定时关闭', skipOffstage: false),
            matching: find.byType(ExcludeFocus),
          ),
        )
        .excluding;
    expect(excluded(), isFalse);
    await tester.tap(find.text('画面'));
    await tester.pumpAndSettle();
    // Hidden, its rows are out of the keyboard's reach.
    expect(excluded(), isTrue);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(excluded(), isFalse);
  });

  testWidgets('back goes to the first level before it leaves', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    await tester.tap(find.text('画面'));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pumpAndSettle();
    // Still here, on the first level.
    expect(find.byType(GroupedSettings), findsOneWidget);
    expect(find.text('定时关闭'), findsOneWidget);
    expect(find.text('选择画质'), findsNothing);
  });

  testWidgets('a drag from the left edge goes back, or comes in again', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    await tester.tap(find.text('画面'));
    await tester.pumpAndSettle();
    final left = tester.getTopLeft(find.byType(GroupedSettings));
    final y = tester.getCenter(find.text('选择画质')).dy;

    // A short slow drag comes back in.
    var drag = await tester.startGesture(Offset(left.dx + 8, y));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    // The group follows the finger.
    expect(tester.getTopLeft(find.text('选择画质')).dx, greaterThan(left.dx + 60));
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('选择画质'), findsOneWidget);
    expect(tester.getTopLeft(find.text('选择画质')).dx, lessThan(left.dx + 80));

    // Past halfway, it goes back.
    drag = await tester.startGesture(Offset(left.dx + 8, y));
    for (var i = 0; i < 25; i++) {
      await drag.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('选择画质'), findsNothing);
    expect(find.text('定时关闭'), findsOneWidget);

    // Away from the edge, a drag does nothing.
    await tester.tap(find.text('画面'));
    await tester.pumpAndSettle();
    await tester.dragFrom(Offset(left.dx + 200, y), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('选择画质'), findsOneWidget);
  });

  testWidgets('with animations off it jumps', (tester) async {
    await pump(tester, disableAnimations: true);
    await tester.pump();
    final left = tester.getTopLeft(find.byType(GroupedSettings)).dx;
    await tester.tap(find.text('画面'));
    await tester.pump();
    await tester.pump();
    // The group stands in place on the next frame, slid in already.
    expect(find.text('选择画质'), findsOneWidget);
    final x = tester.getTopLeft(find.text('选择画质')).dx;
    expect(x - left, lessThan(80));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('选择画质')).dx, x);
  });
}
