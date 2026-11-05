import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<bool> barrierTapCloses(WidgetTester tester, bool barrierCloses) async {
    var heldBack = 0;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      PublishRoute<void>(
        barrierCloses: barrierCloses,
        transitionDuration: const Duration(milliseconds: 100),
        pageBuilder: (context, _, _) => Align(
          alignment: Alignment.bottomCenter,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) heldBack++;
            },
            child: const SizedBox(height: 200, child: Text('面板')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    final closed = find.text('面板').evaluate().isEmpty;
    // Kept open, the PopScope heard the tap as a back.
    if (!closed) expect(heldBack, 1);
    return closed;
  }

  testWidgets('a barrier that closes passes a PopScope by', (tester) async {
    expect(await barrierTapCloses(tester, true), isTrue);
  });

  testWidgets('a plain barrier asks the PopScope first', (tester) async {
    expect(await barrierTapCloses(tester, false), isFalse);
  });
}
