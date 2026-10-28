import 'package:PiliPlus/common/widgets/scaffold/bottom_sheet_layout.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Counts the times the body is painted.
class _Counter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_Counter oldDelegate) => false;
}

Future<MiniScaffoldState> _pumpScaffold(
  WidgetTester tester,
  _Counter body,
) async {
  final key = GlobalKey<MiniScaffoldState>();
  await tester.pumpWidget(
    GetMaterialApp(
      home: MiniScaffold(
        key: key,
        body: CustomPaint(painter: body, child: const SizedBox.expand()),
      ),
    ),
  );
  return key.currentState!;
}

PersistentBottomSheetController _show(
  MiniScaffoldState scaffold, {
  required bool opaque,
  double? height,
}) => scaffold.showBottomSheet(
  constraints: const BoxConstraints(),
  opaque: opaque,
  (context) => ColoredBox(
    color: Colors.white,
    child: SizedBox(width: double.infinity, height: height ?? double.infinity),
  ),
);

/// How many times the body is painted when the layout is painted again.
Future<int> _paintsOfARepaint(WidgetTester tester, _Counter body) async {
  final before = body.paints;
  tester.renderObject(find.byType(BottomSheetLayout)).markNeedsPaint();
  await tester.pump();
  return body.paints - before;
}

void main() {
  testWidgets('an opaque sheet up over all of the body hides it', (
    tester,
  ) async {
    final body = _Counter();
    final scaffold = await _pumpScaffold(tester, body);
    _show(scaffold, opaque: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(await _paintsOfARepaint(tester, body), 1, reason: 'coming up');

    await tester.pumpAndSettle();
    expect(await _paintsOfARepaint(tester, body), 0);
  });

  testWidgets('the body shows again as an opaque sheet goes', (tester) async {
    final body = _Counter();
    final scaffold = await _pumpScaffold(tester, body);
    final sheet = _show(scaffold, opaque: true);
    await tester.pumpAndSettle();
    expect(await _paintsOfARepaint(tester, body), 0);

    sheet.close();
    final before = body.paints;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(body.paints, greaterThan(before), reason: 'from its first frame');

    await tester.pumpAndSettle();
    expect(await _paintsOfARepaint(tester, body), 1);
  });

  testWidgets('an opaque sheet short of the body leaves it painted', (
    tester,
  ) async {
    final body = _Counter();
    final scaffold = await _pumpScaffold(tester, body);
    _show(scaffold, opaque: true, height: 300);
    await tester.pumpAndSettle();
    expect(await _paintsOfARepaint(tester, body), 1);
  });

  testWidgets('a sheet not marked opaque leaves the body painted', (
    tester,
  ) async {
    final body = _Counter();
    final scaffold = await _pumpScaffold(tester, body);
    _show(scaffold, opaque: false);
    await tester.pumpAndSettle();
    expect(await _paintsOfARepaint(tester, body), 1);
  });
}
