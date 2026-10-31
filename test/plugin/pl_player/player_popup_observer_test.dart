import 'package:PiliPlus/plugin/pl_player/utils/player_popup_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Player implements PopupControlsHolder {
  @override
  bool controlsShown = true;
  int held = 0;
  int released = 0;

  @override
  void holdControls() => held++;

  @override
  void releaseControls() => released++;
}

void main() {
  late _Player player;
  late BuildContext home;

  Future<void> pump(WidgetTester tester) async {
    player = _Player();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PlayerPopupObserver(player: () => player)],
        home: Builder(
          builder: (context) {
            home = context;
            return const Scaffold();
          },
        ),
      ),
    );
  }

  void openMenu() => showMenu<int>(
    context: home,
    position: const RelativeRect.fromLTRB(100, 100, 100, 100),
    items: const [PopupMenuItem(value: 1, child: Text('1080P'))],
  );

  testWidgets('a menu over the controls holds them until it has gone back, '
      'not just until it starts back', (tester) async {
    await pump(tester);
    openMenu();
    await tester.pumpAndSettle();
    expect(player.held, 1);

    Navigator.of(home).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Still on its way back into its button.
    expect(player.released, 0);

    await tester.pumpAndSettle();
    expect(player.released, 1);
  });

  testWidgets('a popup over hidden controls holds nothing', (tester) async {
    await pump(tester);
    player.controlsShown = false;
    openMenu();
    await tester.pumpAndSettle();
    Navigator.of(home).pop();
    await tester.pumpAndSettle();

    expect(player.held, 0);
    expect(player.released, 0);
  });

  testWidgets('a page pushed is no popup, and holds nothing', (tester) async {
    await pump(tester);
    Navigator.of(
      home,
    ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();

    expect(player.held, 0);
  });

  testWidgets('a popup removed without its animation back lets go too', (
    tester,
  ) async {
    await pump(tester);
    openMenu();
    await tester.pumpAndSettle();
    Navigator.of(
      home,
    ).removeRoute(ModalRoute.of(tester.element(find.text('1080P')))!);
    await tester.pumpAndSettle();

    expect(player.held, 1);
    expect(player.released, 1);
  });
}
