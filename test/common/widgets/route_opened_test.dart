import 'package:PiliPlus/common/widgets/route_opened.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late int opened;
  late GlobalKey<NavigatorState> navigator;

  Future<void> pumpApp(WidgetTester tester) async {
    opened = 0;
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('首页')),
    );
  }

  Route<void> page() => MaterialPageRoute<void>(
    builder: (_) => RouteOpened(
      onOpened: () => opened++,
      child: const Text('视频页'),
    ),
  );

  testWidgets('waits for the route to open', (tester) async {
    await pumpApp(tester);
    navigator.currentState!.push(page());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('视频页'), findsOneWidget);
    expect(opened, 0);

    await tester.pumpAndSettle();
    expect(opened, 1);

    // Covered and shown again, it has opened already.
    navigator.currentState!.push(page());
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(opened, 2);
  });

  testWidgets('calls at once on a route that is not opening', (tester) async {
    await pumpApp(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RouteOpened(
          onOpened: () => opened++,
          child: const Text('视频页'),
        ),
      ),
    );
    expect(opened, 1);
  });

  testWidgets('never calls on a route popped while it opens', (tester) async {
    await pumpApp(tester);
    navigator.currentState!.push(page());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('视频页'), findsNothing);
    expect(opened, 0);
  });
}
