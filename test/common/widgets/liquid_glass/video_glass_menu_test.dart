import 'dart:io';
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass_menu.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
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

/// How far the card has eased in, its glass's own [VideoGlass.t] or, on the
/// move, the fade of the image it is drawn from.
double _card(WidgetTester tester) {
  final menu = find.byType(VideoGlassMenu);
  final glass = find.descendant(of: menu, matching: find.byType(VideoGlass));
  final pane = tester.widgetList<VideoGlass>(glass).firstWhere((g) => !g.bare);
  final growing = find.ancestor(
    of: find.byWidget(pane),
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_Growing',
    ),
  );
  return pane.t * ((tester.widget(growing.first) as dynamic).opacity as double);
}

/// The card's size, which overshoots as it springs open.
double _scale(WidgetTester tester) =>
    (tester.widget(
          find
              .descendant(
                of: find.byType(VideoGlassMenu),
                matching: find.byWidgetPredicate(
                  (widget) => widget.runtimeType.toString() == '_Growing',
                ),
              )
              .first,
        ) as dynamic).scale
        as double;

/// The fade the rows take with the card.
double _rows(WidgetTester tester) =>
    (tester.widget(
          find.descendant(
            of: find.byType(VideoGlassMenu),
            matching: find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_GrowingRows',
            ),
          ),
        ) as dynamic).opacity
        as double;

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

  testWidgets('closing, the card sets off at once, its rows fading with it, '
      'and is gone well before the route', (tester) async {
    await _open(tester, VideoGlassMenus(child: _qualityButton()));
    await tester.tap(find.text('720P 准高清'));
    await tester.pump();

    final menu = find.byType(VideoGlassMenu);
    var ms = 0;
    var goneBeforeRoute = false;
    // Frame by frame through the route's return, 500 ms.
    while (true) {
      await tester.pump(const Duration(milliseconds: 16));
      ms += 16;
      if (menu.evaluate().isEmpty) break;
      final t = _card(tester);
      final rows = _rows(tester);
      // Not held still, as Material's curve holds the route at first.
      if (ms <= 32) expect(t, lessThan(1), reason: 'at $ms ms');
      if (t > 0) {
        expect(rows, greaterThan(0), reason: 'the card at $t, no rows on it');
      }
      // Under a 255th of itself from 85% of the way, and a frame.
      if (ms >= 441) {
        expect(t, lessThan(1 / 255), reason: 'at $ms ms');
        goneBeforeRoute = true;
      }
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
    double rows() => _rows(tester);
    var last = rows();
    expect(last, lessThan(1));

    var card = _card(tester);

    // Away from the menu, as a tap outside closes it.
    await tester.tapAt(const Offset(5, 5));
    var goneBeforeRoute = false;
    var first = true;
    while (menu.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      if (menu.evaluate().isEmpty) break;
      expect(rows(), lessThanOrEqualTo(last));
      last = rows();
      // On from where the card stood, shrinking at once, never growing on.
      final now = _card(tester);
      expect(now, lessThanOrEqualTo(card));
      if (first) expect(now, greaterThan(card - 0.15));
      first = false;
      card = now;
      if (now < 1 / 255) goneBeforeRoute = true;
    }
    // Not left to follow its opening curve back till the route ends.
    expect(goneBeforeRoute, isTrue);
  });

  testWidgets('opens on the menus\' own spring, its size a little past whole '
      'and back, its glass never past', (tester) async {
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
    // The spring's own overshoot, which a curve to 1 never shows.
    final spring = SpringSimulation(glassMenuOpenSpring, 0, 1, 0);
    var most = 0.0;
    for (var ms = 0; ms <= 600; ms += 4) {
      most = math.max(most, spring.x(ms / 1000));
    }
    var grown = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      grown = math.max(grown, (_scale(tester) - 0.6) / 0.4);
      expect(_card(tester), lessThanOrEqualTo(1));
    }
    expect(grown, greaterThan(1.01));
    expect(grown, closeTo(most, 0.01));
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
  });

  testWidgets('closing, the card shrinks back as the menus\' own glass does '
      'with no button to return into, on the route\'s own time', (
    tester,
  ) async {
    await _open(tester, VideoGlassMenus(child: _qualityButton()));
    await tester.tap(find.text('720P 准高清'));
    await tester.pump();

    final menu = find.byType(VideoGlassMenu);
    final route = ModalRoute.of(tester.element(menu))!.animation!;
    var frames = 0;
    while (true) {
      await tester.pump(const Duration(milliseconds: 16));
      if (menu.evaluate().isEmpty) break;
      // How far into the return, on the route's linear time.
      final share = 1 - glassMenuRouteTime(route);
      expect(
        _card(tester),
        closeTo(1 - Curves.easeOutCubic.transform(share), 0.01),
        reason: '${(share * 100).round()}% into the return',
      );
      frames++;
    }
    expect(frames, greaterThan(20));
  });

  testWidgets('drawn from an image as it grows, each row still fades in on '
      'Material\'s own time, one after another', (tester) async {
    final shot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: GlassSurfaces.themed(ThemeData()),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: VideoGlassMenus(
                child: Builder(
                  builder: (context) => Theme(
                    data: VideoGlass.controlsTheme(Theme.of(context)),
                    child: PopupMenuButton<int>(
                      itemBuilder: (_) => [
                        for (var i = 1; i <= 4; i++)
                          PopupMenuItem(value: i, child: Text('$i$i$i$i')),
                      ],
                      child: const Text('1.0X'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1.0X'));
    await tester.pump();
    // Most of the way open, the last rows still coming in.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 35));
    }
    final rows = tester
        .renderObjectList<RenderAnimatedOpacity>(
          find.descendant(
            of: find.byType(VideoGlassMenu),
            matching: find.byType(FadeTransition),
          ),
        )
        .toList();
    expect(rows, hasLength(4));
    final fades = [for (final row in rows) row.opacity.value];
    expect(fades.first, 1);
    expect(fades.last, lessThan(0.6));

    // How bright each row's text is drawn over the card: its brightest
    // pixel, less the card's beside it.
    final brightness = await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData())!;
      double contrast(Rect rect) {
        var most = 0;
        var least = 255;
        final around = rect.inflate(4);
        for (var y = around.top.ceil(); y < around.bottom; y++) {
          for (var x = around.left.ceil(); x < around.right; x++) {
            final green = bytes.getUint8((y * image.width + x) * 4 + 1);
            most = math.max(most, green);
            least = math.min(least, green);
          }
        }
        return (most - least) / 255;
      }

      return [
        for (var i = 1; i <= 4; i++)
          contrast(tester.getRect(find.text('$i$i$i$i'))),
      ];
    });
    // Each row as bright as Material's fade has it: the last ones dimmer,
    // not all one fade.
    for (var i = 1; i < 4; i++) {
      expect(
        brightness![i],
        closeTo(brightness[0] * fades[i], 0.06),
        reason: 'row ${i + 1} at its fade ${fades[i]}',
      );
    }
    expect(brightness![0], greaterThan(0.5));
    await tester.pumpAndSettle();
  });

  testWidgets('a row pressed as the menu opens stands on its platter at '
      'once, as Material\'s ink draws it', (tester) async {
    final shot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: GlassSurfaces.themed(ThemeData()),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: VideoGlassMenus(child: _qualityButton())),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1080P'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Pressed straight, not slid on into from the button: the menu's
    // scroll view holds the press a moment, then the ink fades in.
    final row = tester.getRect(find.text('720P 准高清'));
    final gesture = await tester.startGesture(row.center);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(
      ModalRoute.of(
            tester.element(find.byType(VideoGlassMenu)),
          )!.animation!.isAnimating ||
          (_scale(tester) - 1).abs() > 1e-3,
      isTrue,
      reason: 'still opening',
    );

    // Past where the row's text ends, its platter, or the card bare.
    final rows = await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData())!;
      int green(Offset at) => bytes.getUint8(
        (at.dy.round() * image.width + at.dx.round()) * 4 + 1,
      );
      final other = tester.getRect(find.text('1080P 高清'));
      return (
        pressed: green(Offset(row.right + 12, row.center.dy)),
        other: green(Offset(other.right + 12, other.center.dy)),
      );
    });
    expect(rows!.pressed, greaterThan(rows.other + 15));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a long menu scrolled as it opens draws each row where it '
      'now stands, as its taps find it', (tester) async {
    final shot = GlobalKey();
    // Long rows and short ones in turn, as many as to scroll.
    String label(int i) => i.isEven ? '$i' : '$i' * 6;
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: GlassSurfaces.themed(ThemeData()),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.topCenter,
              child: VideoGlassMenus(
                child: Builder(
                  builder: (context) => Theme(
                    data: VideoGlass.controlsTheme(Theme.of(context)),
                    child: PopupMenuButton<int>(
                      itemBuilder: (_) => [
                        for (var i = 1; i <= 30; i++)
                          PopupMenuItem(value: i, child: Text(label(i))),
                      ],
                      child: const Text('字幕'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('字幕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // A row on, as a drag scrolls it, still opening.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(VideoGlassMenu),
        matching: find.byType(Scrollable),
      ),
    );
    final step =
        tester.getTopLeft(find.text(label(2))).dy -
        tester.getTopLeft(find.text(label(1))).dy;
    scrollable.position.jumpTo(step);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      ModalRoute.of(tester.element(find.byType(VideoGlassMenu)))!
          .animation!
          .isAnimating,
      isTrue,
    );

    // Past where a short row's text ends, a long row's goes on.
    final rows = [
      for (var i = 2; i <= 5; i++)
        (
          i,
          tester.getRect(find.text(label(i))),
          tester.getRect(find.text(label(i + 1))),
        ),
    ];
    final drawn = await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData())!;
      int green(Offset at) => bytes.getUint8(
        (at.dy.round() * image.width + at.dx.round()) * 4 + 1,
      );
      return [
        for (final (i, rect, next) in rows)
          (
            i,
            green(Offset(math.max(rect.right, next.right) - 4, rect.center.dy)),
          ),
      ];
    });
    final card = drawn!.map((row) => row.$2).reduce(math.min);
    for (final (i, green) in drawn) {
      if (i.isOdd) {
        expect(green, greaterThan(card + 20), reason: 'row $i, a long one');
      } else {
        expect(green, lessThan(card + 10), reason: 'row $i, a short one');
      }
    }
    await tester.pumpAndSettle();
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

    testWidgets('on the move the card runs no filter and fades nothing on a '
        'layer of its own, drawn from images of it at rest, and stands on '
        'live glass once grown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GlassSurfaces.themed(ThemeData()),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                // The video, a texture under the player's box.
                Positioned.fill(
                  child: SizedBox.expand(
                    key: player,
                    child: const Texture(textureId: 1),
                  ),
                ),
                Align(
                  alignment: const Alignment(0.6, 0.8),
                  child: VideoGlassMenus(child: _qualityButton()),
                ),
              ],
            ),
          ),
        ),
      );
      // Filters, which take offscreen passes.
      Iterable<Layer> filters() => tester.layers.where(
        (layer) => layer is ImageFilterLayer || layer is BackdropFilterLayer,
      );
      Iterable<Layer> under(Layer layer) sync* {
        yield layer;
        if (layer is ContainerLayer) {
          for (var child = layer.firstChild; child != null;) {
            yield* under(child);
            child = child.nextSibling;
          }
        }
      }

      // Partway fades, and those that hold a picture, as text, which takes
      // an offscreen layer of its own to fade: a texture alone takes it.
      Iterable<OpacityLayer> fades() => tester.layers
          .whereType<OpacityLayer>()
          .where((layer) => layer.alpha! > 0 && layer.alpha! < 255);
      Iterable<Layer> fadedPictures() => fades().where(
        (layer) => under(layer).any((layer) => layer is PictureLayer),
      );

      await tester.tap(find.text('1080P'));
      await tester.pump();
      // Most of the way open, the rows coming in one after another.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(filters(), isEmpty, reason: 'opening, frame $i');
        expect(fadedPictures(), isEmpty, reason: 'opening, frame $i');
      }
      await tester.pumpAndSettle();
      expect(filters(), isNotEmpty);
      expect(find.text('720P 准高清'), findsOneWidget);

      // Away from the menu, as a tap outside closes it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(filters(), isEmpty, reason: 'closing, frame $i');
        expect(fadedPictures(), isEmpty, reason: 'closing, frame $i');
      }
      // Near its end, the card all but gone, the video drawn again under it
      // fades with it, leaving no hole in what lies under: it alone fades,
      // a texture.
      await tester.pump(const Duration(milliseconds: 150));
      expect(fadedPictures(), isEmpty);
      expect(fades(), isNotEmpty);
      for (final fade in fades()) {
        expect(under(fade).whereType<TextureLayer>(), isNotEmpty);
      }
      await tester.pumpAndSettle();
      expect(find.byType(VideoGlassMenu), findsNothing);
    });

    testWidgets('fading out, past the video\'s edges the card still covers '
        'what lies under it with the black the player has there', (
      tester,
    ) async {
      final shot = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: MaterialApp(
            theme: GlassSurfaces.themed(ThemeData()),
            home: Scaffold(
              body: Stack(
                children: [
                  // A video letterboxed in the player, which shows white
                  // around it, as the controls would under the card.
                  Positioned.fill(
                    child: ColoredBox(
                      key: player,
                      color: Colors.white,
                      child: const Center(
                        child: SizedBox(
                          width: 400,
                          height: 225,
                          child: Texture(textureId: 1),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.95, 0.9),
                    child: VideoGlassMenus(child: _qualityButton()),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('1080P'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      // Most of the way back, the card thin, the black under it fading.
      await tester.pump(const Duration(milliseconds: 220));
      final t = _card(tester);
      final covers = tester
          .widgetList<VideoGlass>(find.byType(VideoGlass))
          .firstWhere((glass) => glass.bare)
          .t;
      expect(covers, inExclusiveRange(0, 1));

      // A point on the card's edge, past the video, where its rows are not.
      final menu = tester.getRect(find.byType(VideoGlassMenu));
      final button = tester.getCenter(find.text('1080P'));
      final scale = _scale(tester);
      Offset scaled(Offset at) => button + (at - button) * scale;
      final at = scaled(Offset(menu.right - 6, menu.center.dy));
      expect(
        tester.getRect(find.byType(Texture)).contains(at),
        isFalse,
        reason: 'the point lies past the video',
      );
      final green = await tester.runAsync(() async {
        final boundary =
            shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!;
        return bytes.getUint8(
          (at.dy.round() * image.width + at.dx.round()) * 4 + 1,
        );
      });
      // Under the card's thin glass, the white shows only as far as the
      // black over it has faded.
      final bare = (1 - t) * 255;
      expect(green, lessThan(bare * (1 - covers) + 30));
      expect(green, lessThan(bare - 40));
      await tester.pumpAndSettle();
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

    final growing = tester.widgetList(
      find.descendant(
        of: find.byType(VideoGlassMenu),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString().startsWith('_Growing'),
        ),
      ),
    );
    expect(growing, isNotEmpty);
    for (final widget in growing) {
      expect((widget as dynamic).scale, 1);
    }
    expect(_card(tester), 1);
    await tester.pumpAndSettle();
  });
}
