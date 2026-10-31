import 'package:PiliPlus/common/widgets/liquid_glass/video_glass_menu.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
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
  // In the player's controls, and beside them on the page, as the live
  // room's chat.
  late BuildContext home;
  late BuildContext chat;

  Future<void> pump(WidgetTester tester) async {
    player = _Player();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PlayerPopupObserver(player: () => player)],
        home: Scaffold(
          body: Column(
            children: [
              VideoGlassMenus(
                child: Builder(
                  builder: (context) {
                    home = context;
                    return const SizedBox(height: 100);
                  },
                ),
              ),
              Builder(
                builder: (context) {
                  chat = context;
                  return const SizedBox(height: 100);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openMenu([BuildContext? from]) => showMenu<int>(
    context: from ?? home,
    position: const RelativeRect.fromLTRB(100, 100, 100, 100),
    items: const [PopupMenuItem(value: 1, child: Text('1080P'))],
  );

  testWidgets('a menu over the controls holds them until it has gone back, '
      'not just until it starts back', (tester) async {
    await pump(tester);
    openMenu();
    // At once, before a hide timed out meanwhile could come.
    expect(player.held, 1);
    await tester.pumpAndSettle();
    expect(player.released, 0);

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

  testWidgets('a dialog over the controls holds them too', (tester) async {
    await pump(tester);
    showDialog<void>(
      context: home,
      builder: (_) => const AlertDialog(content: Text('保存字幕')),
    );
    await tester.pumpAndSettle();
    expect(player.held, 1);

    Navigator.of(home).pop();
    await tester.pumpAndSettle();
    expect(player.released, 1);
  });

  testWidgets('a panel slid in, as 更多设置, or a sheet, holds nothing: the '
      'controls hide under it in their time', (tester) async {
    await pump(tester);
    Navigator.of(home).push(
      PublishRoute<void>(
        pageBuilder: (_, _, _) => const Text('更多设置'),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(home).pop();
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
      context: home,
      builder: (_) => const Text('选集'),
    );
    await tester.pumpAndSettle();
    Navigator.of(home).pop();
    await tester.pumpAndSettle();

    expect(player.held, 0);
    expect(player.released, 0);
  });

  testWidgets('a menu out of a panel, as 超分辨率 in 更多设置, holds nothing', (
    tester,
  ) async {
    await pump(tester);
    late BuildContext panel;
    Navigator.of(home).push(
      PublishRoute<void>(
        pageBuilder: (context, _, _) {
          panel = context;
          return const Text('更多设置');
        },
      ),
    );
    await tester.pumpAndSettle();
    showMenu<int>(
      context: panel,
      position: const RelativeRect.fromLTRB(100, 100, 100, 100),
      items: const [PopupMenuItem(value: 1, child: Text('超分辨率'))],
    );
    await tester.pumpAndSettle();

    // Held as it opened, let go once it had built.
    expect(player.held, player.released);
  });

  testWidgets('a menu out of the page beside the controls, as the live '
      'room\'s chat, holds nothing', (tester) async {
    await pump(tester);
    openMenu(chat);
    await tester.pumpAndSettle();

    expect(find.text('1080P'), findsOneWidget);
    // Held as it opened, let go once it had built.
    expect(player.held, player.released);
  });
}
