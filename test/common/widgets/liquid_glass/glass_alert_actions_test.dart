import 'package:PiliPlus/common/widgets/liquid_glass/glass_alert_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<List<String>> topDown(
    WidgetTester tester,
    List<Widget> actions,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: GlassAlertActions(actions: actions),
          ),
        ),
      ),
    );
    final labels = [
      for (final action in actions)
        ((action as ButtonStyleButton).child! as Text).data!,
    ];
    return labels..sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
  }

  Widget text(String label, {Color? color}) => TextButton(
    onPressed: () {},
    child: Text(label, style: color == null ? null : TextStyle(color: color)),
  );

  testWidgets('a FilledButton is the default, on top of a stack', (
    tester,
  ) async {
    final outline = ThemeData().colorScheme.outline;
    expect(
      await topDown(tester, [
        text('稍后', color: outline),
        text('浏览器下载'),
        FilledButton(onPressed: () {}, child: const Text('下载并安装')),
      ]),
      ['下载并安装', '浏览器下载', '稍后'],
    );
    expect(
      await topDown(tester, [
        text('取消'),
        FilledButton(onPressed: () {}, child: const Text('重试')),
        text('浏览器下载'),
      ]),
      ['重试', '浏览器下载', '取消'],
    );
  });

  testWidgets('without one, the order stays as before', (tester) async {
    expect(
      await topDown(tester, [text('取消'), text('zip'), text('exe')]),
      ['zip', 'exe', '取消'],
    );
    expect(
      await topDown(tester, [text('a'), text('取消'), text('b')]),
      ['a', 'b', '取消'],
    );
  });
}
