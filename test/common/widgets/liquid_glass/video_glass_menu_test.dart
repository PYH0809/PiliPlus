import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass_menu.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// The quality button as the player's bottom bar has it: on the controls'
/// dark theme, with the current quality checked.
Widget _qualityButton({PopupMenuItemSelected<int>? onSelected}) => Builder(
  builder: (context) => Theme(
    data: VideoGlass.controlsTheme(Theme.of(context)),
    child: PopupMenuButton<int>(
      tooltip: '画质',
      initialValue: 80,
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 80, child: Text('1080P 高清')),
        PopupMenuItem(value: 64, child: Text('720P 准高清')),
      ],
      child: const Text('1080P'),
    ),
  ),
);

Future<void> _open(WidgetTester tester, Widget button) async {
  await tester.pumpWidget(
    MaterialApp(
      // The app's theme with the switch on, the menus' labels set from its
      // light scheme.
      theme: GlassSurfaces.themed(ThemeData()),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: button),
      ),
    ),
  );
  await tester.tap(find.text('1080P'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    GlassSurfaces.install();
    // The video's glass reads its mode from the settings.
    tempDir = await Directory.systemTemp.createTemp('piliplus-video-menu-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('a menu out of the player\'s controls is on the video\'s glass, '
      'which reads the video, not the host\'s, which shows black over it', (
    tester,
  ) async {
    await _open(tester, VideoGlassMenus(child: _qualityButton()));

    expect(find.byType(VideoGlassMenu), findsOneWidget);
    expect(find.byType(GlassMenuMorph), findsNothing);
    expect(find.text('720P 准高清'), findsOneWidget);
  });

  testWidgets('elsewhere a menu keeps the menus\' own glass', (tester) async {
    await _open(tester, _qualityButton());

    expect(find.byType(GlassMenuMorph), findsOneWidget);
    expect(find.byType(VideoGlassMenu), findsNothing);
  });

  testWidgets('on the dark glass the current quality\'s check is light', (
    tester,
  ) async {
    await _open(tester, VideoGlassMenus(child: _qualityButton()));

    final check = find.byIcon(Icons.check_rounded);
    expect(check, findsOneWidget);
    final color = IconTheme.of(tester.element(check)).color!;
    expect(color.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('a press on the button carried on into the menu picks the row '
      'it lets go on, as on the menus\' own glass', (tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassSurfaces.themed(ThemeData()),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: VideoGlassMenus(
              child: _qualityButton(onSelected: (value) => picked = value),
            ),
          ),
        ),
      ),
    );

    // The menu opens on the press, and the finger slides on to a row.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('1080P')),
    );
    await tester.pumpAndSettle();
    await gesture.moveTo(tester.getCenter(find.text('720P 准高清')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(picked, 64);
    expect(find.byType(VideoGlassMenu), findsNothing);
  });

  testWidgets('a row lit while the menu still grows stays lit where it is '
      'once grown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassSurfaces.themed(ThemeData()),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: VideoGlassMenus(child: _qualityButton())),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('1080P')),
    );
    // A third of the way open, the card still small.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(tester.getCenter(find.text('720P 准高清')));
    await tester.pump();
    // Held still while it grows the rest of the way.
    await tester.pumpAndSettle();

    final rows = find.descendant(
      of: find.byType(VideoGlassMenu),
      matching: find.byType(CustomPaint),
    );
    final paint = tester.widget<CustomPaint>(rows.first);
    final platter = ((paint.painter! as dynamic).row as Rect).shift(
      tester.getTopLeft(rows.first),
    );
    // On the row: its middle where the row's text is.
    final text = tester.getCenter(find.text('720P 准高清'));
    expect((platter.center.dy - text.dy).abs(), lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('closing, the rows fade with the card, not before it, and '
      'the card is gone well before the route', (tester) async {
    await _open(tester, VideoGlassMenus(child: _qualityButton()));
    await tester.tap(find.text('720P 准高清'));
    await tester.pump();

    final menu = find.byType(VideoGlassMenu);
    final glass = find.descendant(of: menu, matching: find.byType(VideoGlass));
    final route = ModalRoute.of(tester.element(menu))!.animation!;
    var goneBeforeRoute = false;
    // Frame by frame through the route's return.
    while (menu.evaluate().isNotEmpty) {
      final t = tester.widget<VideoGlass>(glass).t;
      final rows = tester
          .widget<Opacity>(
            find.descendant(of: glass, matching: find.byType(Opacity)).first,
          )
          .opacity;
      if (t > 0) {
        expect(rows, greaterThan(0), reason: 'the card at $t, no rows on it');
      }
      // Two fifths of the return left, the card is gone.
      if (route.value <= 0.4) {
        expect(t, 0, reason: 'the route at ${route.value}');
        goneBeforeRoute = true;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(goneBeforeRoute, isTrue);
  });

  testWidgets('closed as it still grows, the rows fade on from where they '
      'stood, never brighter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassSurfaces.themed(ThemeData()),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: VideoGlassMenus(child: _qualityButton())),
        ),
      ),
    );
    await tester.tap(find.text('1080P'));
    await tester.pump();
    // Partway open, the rows only coming in.
    await tester.pump(const Duration(milliseconds: 60));

    final menu = find.byType(VideoGlassMenu);
    double rows() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.descendant(
                  of: menu,
                  matching: find.byType(VideoGlass),
                ),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    var last = rows();
    expect(last, lessThan(1));

    // Away from the menu, as a tap outside closes it.
    await tester.tapAt(const Offset(5, 5));
    while (menu.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      if (menu.evaluate().isEmpty) break;
      expect(rows(), lessThanOrEqualTo(last));
      last = rows();
    }
  });

  group('the player\'s box', () {
    final player = GlobalKey();
    setUp(
      () => VideoGlassSource.player = (
        video: player,
        changes: ChangeNotifier(),
      ),
    );
    tearDown(() => VideoGlassSource.player = null);

    // The quality button at the foot of a player [height] tall, as its bar
    // has it.
    Future<void> openOnPlayer(
      WidgetTester tester,
      double height, {
      double zoom = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GlassSurfaces.themed(ThemeData()),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 400,
                height: height,
                child: Stack(
                  children: [
                    // The video, zoomed in as a pinch does, clipped to the
                    // player.
                    Positioned.fill(
                      child: ClipRect(
                        child: Transform.scale(
                          scale: zoom,
                          child: SizedBox.expand(key: player),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: VideoGlassMenus(child: _qualityButton()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('1080P'));
      await tester.pumpAndSettle();
    }

    Finder drawsVideo() => find.descendant(
      of: find.byType(VideoGlassMenu),
      matching: find.byType(VideoGlassSource),
    );

    testWidgets('a menu on the player draws its video', (tester) async {
      await openOnPlayer(tester, 600);
      expect(drawsVideo(), findsOneWidget);
    });

    testWidgets('a menu reaching past a small player reads the screen, the '
        'page past the player not drawn black', (tester) async {
      await openOnPlayer(tester, 60);
      expect(find.byType(VideoGlassMenu), findsOneWidget);
      expect(drawsVideo(), findsNothing);
    });

    testWidgets('so it does past a small player zoomed in, its video reaching '
        'past what shows of it', (tester) async {
      await openOnPlayer(tester, 60, zoom: 6);
      expect(find.byType(VideoGlassMenu), findsOneWidget);
      expect(drawsVideo(), findsNothing);
    });
  });

  testWidgets('a menu out of a dialog the controls opened is over the '
      'dialog, not the video, and keeps the menus\' own glass', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassSurfaces.themed(ThemeData()),
        home: Scaffold(
          body: Center(
            child: VideoGlassMenus(
              child: Builder(
                builder: (context) => TextButton(
                  // As 保存字幕 opens its dialog, its format a menu in it.
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(child: _qualityButton()),
                  ),
                  child: const Text('保存字幕'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('保存字幕'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080P'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassMenuMorph), findsOneWidget);
    expect(find.byType(VideoGlassMenu), findsNothing);
  });

  testWidgets('a press held still as the menu grows lights the row that '
      'letting go there picks', (tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassSurfaces.themed(ThemeData()),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: const Alignment(0.6, 0.8),
            child: VideoGlassMenus(
              child: PopupMenuButton<int>(
                tooltip: '倍速',
                onSelected: (value) => picked = value,
                itemBuilder: (_) => [
                  for (var i = 1; i <= 6; i++)
                    PopupMenuItem(value: i, child: Text('${i}X')),
                ],
                child: const Text('1.0X'),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('1.0X')),
    );
    // Early on, the card still small, on to the row farthest from the
    // button, and held there.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final finger = tester.getCenter(find.text('1X'));
    await gesture.moveTo(finger);
    await tester.pump();
    await tester.pumpAndSettle();

    final rows = find.descendant(
      of: find.byType(VideoGlassMenu),
      matching: find.byType(CustomPaint),
    );
    final paint = tester.widget<CustomPaint>(rows.first);
    final platter = ((paint.painter! as dynamic).row as Rect).shift(
      tester.getTopLeft(rows.first),
    );
    expect(platter.contains(finger), isTrue);
    // The row lit.
    final lit = [
      for (var i = 1; i <= 6; i++)
        if (platter.contains(tester.getCenter(find.text('${i}X')))) i,
    ];
    expect(lit, hasLength(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, lit.single);
  });

  testWidgets('with animations off the menu stands grown at once, as the '
      'menus\' own glass does', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassSurfaces.themed(ThemeData()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Center(child: VideoGlassMenus(child: _qualityButton())),
        ),
      ),
    );
    await tester.tap(find.text('1080P'));
    await tester.pump();
    await tester.pump();

    final grow = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(VideoGlassMenu),
            matching: find.byType(Transform),
          )
          .first,
    );
    // Its x scale: Transform.scale leaves z at 1.
    expect(grow.transform.storage[0], 1);
    await tester.pumpAndSettle();
  });
}
