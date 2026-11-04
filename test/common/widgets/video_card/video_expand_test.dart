import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/video_expand.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _card = Rect.fromLTWH(20, 300, 180, 200);
const _screen = Rect.fromLTWH(0, 0, 400, 800);
const _coverFrom = Rect.fromLTWH(20, 300, 180, 112.5);
const _coverTo = Rect.fromLTWH(0, 24, 400, 225);

VideoExpandFrame _at(
  double t, {
  bool returning = false,
  bool interrupted = false,
  bool videoShown = false,
}) => VideoExpandFrame.at(
  t,
  returning: returning,
  interrupted: interrupted,
  card: _card,
  screen: _screen,
  coverFrom: _coverFrom,
  coverTo: _coverTo,
  videoShown: videoShown,
);

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left));
  expect(actual.top, moreOrLessEquals(expected.top));
  expect(actual.right, moreOrLessEquals(expected.right));
  expect(actual.bottom, moreOrLessEquals(expected.bottom));
}

/// The video page as the route builds it, its player marked.
class _Page extends StatelessWidget {
  const _Page({this.watchVideo});

  final VoidCallback Function(VoidCallback shown)? watchVideo;

  @override
  Widget build(BuildContext context) {
    final arguments = Get.arguments as Map;
    // As the video page may be dark in a light app.
    return Theme(
      data: _darkPage,
      child: Scaffold(
        body: Column(
          children: [
            // The player, built over the target, draws the cover over its
            // video and under its controls.
            const SizedBox(
              key: _playerKey,
              height: 225,
              child: Stack(
                children: [
                  ColoredBox(color: Colors.black, child: SizedBox.expand()),
                  VideoExpandCover(),
                  Text('控件'),
                ],
              ),
            ),
            SizedBox(
              height: 225,
              // A new key builds the player anew, as a turned screen does.
              child: ValueListenableBuilder(
                valueListenable: _playerBuilds,
                // None while it is negative, as in picture in picture.
                builder: (context, builds, _) => builds < 0
                    ? const SizedBox.shrink()
                    : VideoExpandTarget(
                        key: ValueKey(builds),
                        watchVideo: watchVideo ?? (shown) => () {},
                      ),
              ),
            ),
            GestureDetector(
              onTap: () => _pageTaps++,
              child: Text('视频页 ${arguments['cid']}'),
            ),
            // Paints whenever _pageChanges changes, if the page is drawn.
            CustomPaint(
              size: const Size.square(20),
              painter: _CountingPainter(_pageChanges, () => _pagePaints++),
            ),
          ],
        ),
      ),
    );
  }
}

final _darkPage = ThemeData.dark();

late ui.Image _coverImage;
const _playerKey = Key('player');
var _pageTaps = 0;
final _playerBuilds = ValueNotifier(0);
final _pageChanges = ValueNotifier(0);
var _pagePaints = 0;

Widget _card0({
  ValueChanged<VideoExpandSourceState>? onSource,
  Color? tint,
  bool takesPressShot = true,
}) => VideoExpandSource(
  color: Colors.white,
  takesPressShot: takesPressShot,
  builder: (context, source) {
    onSource?.call(source);
    // On a Material of its own, as the app's cards are, which its ink
    // paints on.
    return SizedBox(
      width: 180,
      height: 200,
      child: Material(
        type: .transparency,
        child: InkWell(
          onTap: () => PageUtils.toVideoPage(
            aid: 2,
            bvid: 'BV1xx411c7mD',
            cid: 3,
            title: '标题',
            expandFrom: source,
          ),
          child: Column(
            children: [
              source.cover(
                RawImage(
                  image: _coverImage,
                  width: 180,
                  height: 112.5,
                  color: tint,
                  colorBlendMode: tint == null ? null : BlendMode.modulate,
                ),
              ),
              const Text('卡片'),
            ],
          ),
        ),
      ),
    );
  },
);

Offset _coverCenter(WidgetTester tester) =>
    tester.getCenter(find.byType(RawImage).first);

Future<void> _pump(
  WidgetTester tester, {
  Widget? home,
  bool disableAnimations = false,
  VoidCallback Function(VoidCallback shown)? watchVideo,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      getPages: [
        GetPage(
          name: '/videoV',
          page: () => _Page(watchVideo: watchVideo),
        ),
      ],
      home: Scaffold(
        body: Align(alignment: .topLeft, child: home ?? _card0()),
      ),
    ),
  );
}

double _cardOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.text('卡片', skipOffstage: false),
            matching: find.byType(Opacity, skipOffstage: false),
          )
          .first,
    )
    .opacity;

bool _expanding(WidgetTester tester) =>
    VideoExpandRoute.of(
      tester.element(find.byType(_Page, skipOffstage: false)),
    ) !=
    null;

/// An image from the app's assets, as NetworkImgLayer's placeholder, loaded
/// at once.
class _Placeholder extends AssetBundleImageProvider {
  const _Placeholder();

  @override
  Future<AssetBundleImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(
        AssetBundleImageKey(bundle: rootBundle, name: 'loading', scale: 1),
      );

  @override
  ImageStreamCompleter loadImage(
    AssetBundleImageKey key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture(ImageInfo(image: _coverImage.clone())),
  );
}

/// Counts its paints, repainting whenever [repaint] changes.
class _CountingPainter extends CustomPainter {
  _CountingPainter(this.repaint, this.onPaint) : super(repaint: repaint);

  final Listenable repaint;
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-video-expand-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    _coverImage = await createTestImage(width: 160, height: 100);
  });

  tearDownAll(() async {
    _coverImage.dispose();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() => VideoExpand.debugMobile = true);

  tearDown(() async {
    VideoExpand.debugMobile = null;
    _playerBuilds.value = 0;
    await GStorage.setting.delete(SettingBoxKey.videoExpand);
    Get.reset();
  });

  group('frame', () {
    test('opens from the card to the screen', () {
      final start = _at(0);
      _expectRect(start.rect, _card);
      expect(start.radius, 12);
      expect(start.cardOpacity, 1);
      expect(start.pageOpacity, 0);
      expect(start.scrim, 0);
      _expectRect(start.cover!, _coverFrom);
      expect(start.coverOpacity, 1);

      // The card fades out over the first fifth, the scrim darkens with it.
      final early = _at(0.1);
      final shape = Curves.fastOutSlowIn.transform(0.1);
      _expectRect(early.rect, Rect.lerp(_card, _screen, shape)!);
      expect(early.radius, moreOrLessEquals(12 * (1 - shape)));
      expect(early.cardOpacity, moreOrLessEquals(0.5));
      expect(early.pageOpacity, 0);
      expect(early.scrim, moreOrLessEquals(0.5));

      // The page fades in over the rest.
      final middle = _at(0.6);
      expect(middle.cardOpacity, 0);
      expect(middle.pageOpacity, moreOrLessEquals(0.5));
      expect(middle.scrim, 1);
      _expectRect(
        middle.cover!,
        Rect.lerp(_coverFrom, _coverTo, Curves.fastOutSlowIn.transform(0.6))!,
      );

      final end = _at(1);
      _expectRect(end.rect, _screen);
      expect(end.radius, 0);
      expect(end.pageOpacity, 1);
      _expectRect(end.cover!, _coverTo);
    });

    test('returns with the fades reversed in time', () {
      final start = _at(1, returning: true);
      _expectRect(start.rect, _screen);
      expect(start.pageOpacity, 1);
      expect(start.cardOpacity, 0);
      expect(start.scrim, 1);

      // The page fades out over the return's first fifth.
      final early = _at(0.9, returning: true);
      final shape = Curves.fastOutSlowIn.flipped.transform(0.9);
      _expectRect(early.rect, Rect.lerp(_card, _screen, shape)!);
      expect(early.pageOpacity, moreOrLessEquals(0.5));
      expect(early.cardOpacity, 0);
      expect(early.scrim, moreOrLessEquals(shape));

      // The card fades in over the rest.
      final late = _at(0.4, returning: true);
      expect(late.pageOpacity, 0);
      expect(late.cardOpacity, moreOrLessEquals(0.5));

      final end = _at(0, returning: true);
      _expectRect(end.rect, _card);
      expect(end.radius, 12);
      expect(end.cardOpacity, 1);
      expect(end.scrim, 0);
      _expectRect(end.cover!, _coverFrom);
    });

    test('the cover fades back in over the video as the page fades out', () {
      expect(
        _at(0.9, returning: true, videoShown: true).coverOpacity,
        moreOrLessEquals(0.5),
      );
      expect(_at(0.5, returning: true, videoShown: true).coverOpacity, 1);
      expect(_at(0.9, returning: true).coverOpacity, 1);
    });

    test('a return that interrupted the opening runs it back as it was', () {
      for (final t in [0.1, 0.5, 0.9]) {
        final back = _at(t, returning: true, interrupted: true);
        final open = _at(t);
        _expectRect(back.rect, open.rect);
        _expectRect(back.cover!, open.cover!);
        expect(back.radius, moreOrLessEquals(open.radius));
        expect(back.pageOpacity, moreOrLessEquals(open.pageOpacity));
        expect(back.cardOpacity, open.cardOpacity);
        expect(back.scrim, open.scrim);
        expect(back.coverOpacity, 1);
      }
    });

    test('a card moving its content lands it on the page\'s, crossing in', () {
      // The detail lays the dynamic out at the page's width, under its bar,
      // and longer, its text unfolded.
      const contentTo = Rect.fromLTWH(0, 80, 400, 600);
      VideoExpandFrame at(double t, {bool returning = false}) =>
          VideoExpandFrame.at(
            t,
            returning: returning,
            card: _card,
            screen: _screen,
            contentTo: contentTo,
          );
      final start = at(0);
      _expectRect(start.content!, _card);
      expect(start.contentOpacity, 1);
      expect(start.cardOpacity, 0);
      expect(start.pageOpacity, 0);
      expect(start.cover, isNull);

      // Its top left corner onto the page's, at its own size.
      const landed = Rect.fromLTWH(0, 80, 180, 200);
      final middle = at(0.5);
      _expectRect(
        middle.content!,
        Rect.lerp(_card, landed, Curves.fastOutSlowIn.transform(0.5))!,
      );
      expect(middle.contentOpacity, 1);
      expect(middle.pageOpacity, 0);

      // The page fades in over the last of it, the content out as it lands.
      final late = at(0.85);
      expect(late.pageOpacity, moreOrLessEquals(0.5));
      expect(late.contentOpacity, moreOrLessEquals(0.6));
      final end = at(1);
      _expectRect(end.content!, landed);
      expect(end.contentOpacity, 0);
      expect(end.pageOpacity, 1);
      _expectRect(end.rect, _screen);

      // Returning, the same backwards in time.
      final back = at(0.85, returning: true);
      expect(back.pageOpacity, moreOrLessEquals(0.5));
      expect(back.contentOpacity, moreOrLessEquals(0.6));
      _expectRect(at(0, returning: true).content!, _card);

      // Wider than the page lays it out, it shrinks to fit.
      final narrow = VideoExpandFrame.at(
        1,
        returning: false,
        card: _card,
        screen: _screen,
        contentTo: const Rect.fromLTWH(0, 80, 90, 600),
      );
      _expectRect(narrow.content!, const Rect.fromLTWH(0, 80, 90, 100));
    });

    test('runs only on phones with the switch on and animations on', () {
      expect(
        VideoExpand.allows(
          setting: true,
          disableAnimations: false,
          mobile: true,
        ),
        isTrue,
      );
      expect(
        VideoExpand.allows(
          setting: false,
          disableAnimations: false,
          mobile: true,
        ),
        isFalse,
      );
      expect(
        VideoExpand.allows(
          setting: true,
          disableAnimations: true,
          mobile: true,
        ),
        isFalse,
      );
      expect(
        VideoExpand.allows(
          setting: true,
          disableAnimations: false,
          mobile: false,
        ),
        isFalse,
      );
    });
  });

  testWidgets('a card opens /videoV out of itself, with its arguments', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    expect(Get.currentRoute, '/videoV');
    expect((Get.arguments as Map)['cid'], 3);
    expect((Get.arguments as Map)['title'], '标题');
    expect(_expanding(tester), isTrue);

    // The card hides a frame on, while the page grows over it.
    await tester.pump(const Duration(milliseconds: 16));
    expect(_cardOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('视频页 3'), findsOneWidget);

    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_cardOpacity(tester), 0);
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(_cardOpacity(tester), 1);
  });

  testWidgets('the page under the card is drawn from a picture of it', (
    tester,
  ) async {
    var paints = 0;
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await _pump(
      tester,
      home: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          CustomPaint(
            size: const Size.square(40),
            painter: _CountingPainter(changes, () => paints++),
          ),
          _card0(),
        ],
      ),
    );
    Future<bool> repaintsBelow() async {
      final before = paints;
      changes.value++;
      await tester.pump(const Duration(milliseconds: 16));
      return paints > before;
    }

    await tester.tap(find.text('卡片'));
    await tester.pump();
    // The page shows a frame on, and covers the page below from then.
    await tester.pump(const Duration(milliseconds: 16));
    expect(await repaintsBelow(), isFalse);

    await tester.pumpAndSettle();
    final route = VideoExpandRoute.of(tester.element(find.byType(_Page)))!;
    // Opened, it keeps the picture for the return, which then draws the
    // page below from its first frame on.
    expect(route.debugHoldsBelow, isTrue);
    final before = paints;
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(paints, before);
    expect(find.text('视频页 3'), findsOneWidget);
    expect(await repaintsBelow(), isFalse);

    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(await repaintsBelow(), isTrue);
  });

  testWidgets('a press held on the card takes the page below before the tap', (
    tester,
  ) async {
    await _pump(tester);
    final press = await tester.startGesture(_coverCenter(tester));
    await tester.pump(VideoExpandSourceState.pressHold);
    await tester.pump(const Duration(milliseconds: 40));
    await press.up();
    await tester.pump();
    expect(Get.currentRoute, '/videoV');
    await tester.pump(const Duration(milliseconds: 16));
    final route = VideoExpandRoute.of(tester.element(find.byType(_Page)))!;
    expect(route.debugHoldsBelow, isTrue);
    expect(route.debugBelowTakenOnPress, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('a card moved since the press takes the page again', (
    tester,
  ) async {
    final top = ValueNotifier(0.0);
    addTearDown(top.dispose);
    await _pump(
      tester,
      home: ValueListenableBuilder(
        valueListenable: top,
        builder: (context, value, child) => Padding(
          padding: .only(top: value),
          child: child,
        ),
        child: _card0(),
      ),
    );
    final press = await tester.startGesture(_coverCenter(tester));
    await tester.pump(VideoExpandSourceState.pressHold);
    await tester.pump(const Duration(milliseconds: 16));
    // As a list scrolled while the card's tap waited for a request.
    top.value = 3;
    await tester.pump();
    await press.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final route = VideoExpandRoute.of(tester.element(find.byType(_Page)))!;
    expect(route.debugHoldsBelow, isTrue);
    expect(route.debugBelowTakenOnPress, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('a quick tap or a press that scrolls takes it at the tap', (
    tester,
  ) async {
    await _pump(tester);
    // Moved past the touch slop before it held still long enough, the press
    // took nothing; nor does a tap lifted at once.
    final press = await tester.startGesture(_coverCenter(tester));
    await press.moveBy(const Offset(0, kTouchSlop + 4));
    await tester.pump(VideoExpandSourceState.pressHold * 2);
    await press.cancel();
    await tester.pump();
    await tester.tap(find.text('卡片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final route = VideoExpandRoute.of(tester.element(find.byType(_Page)))!;
    expect(route.debugHoldsBelow, isTrue);
    expect(route.debugBelowTakenOnPress, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a press off the cover or on a card that cannot open takes none',
    (
      tester,
    ) async {
      await _pump(tester);
      // The card's own buttons lie beside the cover.
      var press = await tester.startGesture(tester.getCenter(find.text('卡片')));
      await tester.pump(VideoExpandSourceState.pressHold * 2);
      expect(VideoExpandSourceState.debugHoldsPressShot, isFalse);
      await press.cancel();

      await _pump(tester, home: _card0(takesPressShot: false));
      press = await tester.startGesture(_coverCenter(tester));
      await tester.pump(VideoExpandSourceState.pressHold * 2);
      expect(VideoExpandSourceState.debugHoldsPressShot, isFalse);
      await press.cancel();
      await tester.pump();
    },
  );

  testWidgets('a new press lets the picture of the one before go', (
    tester,
  ) async {
    await _pump(tester);
    final first = await tester.startGesture(_coverCenter(tester));
    await tester.pump(VideoExpandSourceState.pressHold * 2);
    expect(VideoExpandSourceState.debugHoldsPressShot, isTrue);
    // A second finger, as any next press: only the last press holds one.
    final second = await tester.startGesture(
      tester.getCenter(find.text('卡片')),
      pointer: 2,
    );
    await tester.pump();
    expect(VideoExpandSourceState.debugHoldsPressShot, isFalse);
    await second.cancel();
    await first.cancel();
    await tester.pump();
  });

  testWidgets('the page painted since the press takes it again', (
    tester,
  ) async {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await _pump(
      tester,
      home: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          CustomPaint(
            size: const Size.square(40),
            painter: _CountingPainter(changes, () {}),
          ),
          _card0(),
        ],
      ),
    );
    final press = await tester.startGesture(_coverCenter(tester));
    await tester.pump(VideoExpandSourceState.pressHold * 2);
    expect(VideoExpandSourceState.debugHoldsPressShot, isTrue);
    // As another cover loading in place, the layout as it was.
    changes.value++;
    await tester.pump();
    await press.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final route = VideoExpandRoute.of(tester.element(find.byType(_Page)))!;
    expect(route.debugHoldsBelow, isTrue);
    expect(route.debugBelowTakenOnPress, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('a page opened over it lets the picture below go', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    final route = VideoExpandRoute.of(tester.element(find.byType(_Page)))!;
    expect(route.debugHoldsBelow, isTrue);

    // With arguments, as the page under it reads them as it rebuilds.
    Get.to<void>(() => const Text('上面的页'), arguments: {'cid': 3});
    await tester.pumpAndSettle();
    expect(route.debugHoldsBelow, isFalse);

    // Back on top, it takes the picture again as it returns.
    Get.back<void>();
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(route.debugHoldsBelow, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
  });

  testWidgets('the page is drawn from a picture while it moves', (
    tester,
  ) async {
    Future<bool> pagePaints() async {
      final before = _pagePaints;
      _pageChanges.value++;
      await tester.pump(const Duration(milliseconds: 16));
      return _pagePaints > before;
    }

    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    // Shown from a fifth in, drawn live once, so its glass catches what lies
    // behind it, then from a picture of it.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(await pagePaints(), isFalse);

    await tester.pumpAndSettle();
    // At rest it draws itself.
    expect(await pagePaints(), isTrue);

    // Setting off back, it is taken at once: it was drawn live.
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(await pagePaints(), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('a return cutting the opening short keeps its picture', (
    tester,
  ) async {
    Future<bool> pagePaints() async {
      final before = _pagePaints;
      _pageChanges.value++;
      await tester.pump(const Duration(milliseconds: 16));
      return _pagePaints > before;
    }

    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(await pagePaints(), isFalse);

    // Back halfway: the page stays drawn from its picture, not hidden a
    // frame to be drawn whole again.
    Get.back<void>();
    await tester.pump();
    expect(await pagePaints(), isFalse);
    expect(await pagePaints(), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('the page takes no taps while it moves', (tester) async {
    _pageTaps = 0;
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('视频页 3'), warnIfMissed: false);
    expect(_pageTaps, 0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频页 3'));
    expect(_pageTaps, 1);
  });

  testWidgets('the page fades in over its own background', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    final route = VideoExpandRoute.of(
      tester.element(find.byType(_Page, skipOffstage: false)),
    )!;
    // The page's theme, dark, not the app's.
    expect(route.debugPageColor, _darkPage.scaffoldBackgroundColor);
    await tester.pumpAndSettle();
  });

  testWidgets('a second tap while the page opens opens nothing more', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    // The card has not hidden yet: it hides as the page first shows.
    await tester.tap(find.text('卡片'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsOneWidget);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(Get.currentRoute, '/');
  });

  testWidgets('back while the page opens returns it into the card', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('视频页 3'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(_cardOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cover stays over the player until the video shows', (
    tester,
  ) async {
    VoidCallback? shown;
    var stopped = false;
    await _pump(
      tester,
      watchVideo: (onShown) {
        shown = onShown;
        return () => stopped = true;
      },
    );
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    final cover = find.descendant(
      of: find.byType(VideoExpandTarget),
      matching: find.byType(CustomPaint),
    );
    final overVideo = find.descendant(
      of: find.byKey(_playerKey),
      matching: find.byType(CustomPaint),
    );
    expect(cover, findsOneWidget);
    expect(overVideo, findsOneWidget);
    expect(find.text('控件'), findsOneWidget);

    shown!();
    expect(stopped, isTrue);
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
    expect(overVideo, findsNothing);
  });

  testWidgets('a player built again once the cover went shows it no more', (
    tester,
  ) async {
    VoidCallback? shown;
    await _pump(
      tester,
      watchVideo: (onShown) {
        shown = onShown;
        return () {};
      },
    );
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    shown!();
    await tester.pumpAndSettle();
    final cover = find.descendant(
      of: find.byType(VideoExpandTarget),
      matching: find.byType(CustomPaint),
    );
    expect(cover, findsNothing);

    // The video paused, the screen turns.
    _playerBuilds.value++;
    await tester.pump();
    expect(cover, findsNothing);
  });

  testWidgets('a player built again before the video shows lets go in time', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    _playerBuilds.value++;
    await tester.pump();
    final cover = find.descendant(
      of: find.byType(VideoExpandTarget),
      matching: find.byType(CustomPaint),
    );
    expect(cover, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
  });

  testWidgets('a player built again keeps to the first deadline', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    final cover = find.descendant(
      of: find.byType(VideoExpandTarget),
      matching: find.byType(CustomPaint),
    );
    await tester.pump(const Duration(seconds: 3));
    _playerBuilds.value++;
    await tester.pump();
    expect(cover, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
  });

  testWidgets('the cover lets go though no player holds it then', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    _playerBuilds.value = -1;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    _playerBuilds.value = 1;
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(VideoExpandTarget),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('the cover keeps the color the card blends into it', (
    tester,
  ) async {
    const tint = Color(0xFFBBBBBB);
    await _pump(tester, home: _card0(tint: tint));
    await tester.tap(find.text('卡片'));
    await tester.pump();
    final route = VideoExpandRoute.of(
      tester.element(find.byType(_Page, skipOffstage: false)),
    )!;
    expect(
      route.coverFilter,
      const ColorFilter.mode(tint, BlendMode.modulate),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the cover lets go after a while if the video never shows', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    final cover = find.descendant(
      of: find.byType(VideoExpandTarget),
      matching: find.byType(CustomPaint),
    );
    expect(cover, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
  });

  testWidgets('a page whose card has gone returns with a plain fade', (
    tester,
  ) async {
    final showCard = ValueNotifier(true);
    addTearDown(showCard.dispose);
    await _pump(
      tester,
      home: ValueListenableBuilder(
        valueListenable: showCard,
        builder: (context, show, _) =>
            show ? _card0() : const SizedBox.shrink(),
      ),
    );
    await tester.tap(find.text('卡片'));
    await tester.pumpAndSettle();
    showCard.value = false;
    await tester.pump();
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('视频页 3'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card still loading its cover grows no placeholder', (
    tester,
  ) async {
    await _pump(
      tester,
      home: VideoExpandSource(
        color: Colors.white,
        builder: (context, source) => SizedBox(
          width: 180,
          height: 200,
          child: InkWell(
            onTap: () => PageUtils.toVideoPage(
              aid: 2,
              bvid: 'BV1xx411c7mD',
              cid: 3,
              expandFrom: source,
            ),
            child: Column(
              children: [
                source.cover(
                  const Image(
                    image: _Placeholder(),
                    width: 180,
                    height: 112.5,
                  ),
                ),
                const Text('卡片'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    await tester.tap(find.text('卡片'));
    await tester.pump();
    final route = VideoExpandRoute.of(
      tester.element(find.byType(_Page, skipOffstage: false)),
    )!;
    expect(route.cover, isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a video built apart from its card opens out of the card', (
    tester,
  ) async {
    // As a dynamic's: its video, a forwarded one's too, is built by panels
    // that only find the card around them.
    final video = Builder(
      builder: (context) => InkWell(
        onTap: () => PageUtils.toVideoPage(
          aid: 2,
          bvid: 'BV1xx411c7mD',
          cid: 3,
          expandFrom: VideoExpandSource.maybeOf(context),
        ),
        child: Builder(
          builder: (context) => VideoExpandSource.maybeOf(context)!.cover(
            RawImage(image: _coverImage, width: 180, height: 112.5),
          ),
        ),
      ),
    );
    await _pump(
      tester,
      home: VideoExpandSource(
        color: Colors.white,
        builder: (context, source) => SizedBox(
          width: 180,
          height: 200,
          child: Column(children: [const Text('卡片'), video]),
        ),
      ),
    );
    await tester.tap(find.byType(RawImage));
    await tester.pump();
    expect(_expanding(tester), isTrue);
    final route = VideoExpandRoute.of(
      tester.element(find.byType(_Page, skipOffstage: false)),
    )!;
    expect(route.cover, isNotNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a card moving its content opens and returns', (tester) async {
    late VideoExpandSourceState card;
    await _pump(tester, home: _card0(onSource: (source) => card = source));
    expect(
      card.expand<void>(
        '/videoV',
        arguments: {'cid': 3},
        parameters: {'id': '7'},
        moveContent: true,
      ),
      isNotNull,
    );
    await tester.pump();
    final route = VideoExpandRoute.of(
      tester.element(find.byType(_Page, skipOffstage: false)),
    )!;
    expect(route.moveContent, isTrue);
    // No cover of its own: the card's picture is what moves.
    expect(route.cover, isNull);
    expect(Get.parameters['id'], '7');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsOneWidget);

    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(_cardOpacity(tester), 1);
  });

  testWidgets('a card gone while its detail loads opens it as before', (
    tester,
  ) async {
    // As a dynamic with a folded link, fetched whole before it opens: the
    // list may have refreshed its card away by the time it is back.
    late VideoExpandSourceState card;
    await _pump(tester, home: _card0(onSource: (source) => card = source));
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: Text('刷新后的列表'))),
    );
    expect(
      card.expand<void>(
        '/videoV',
        arguments: {'cid': 3},
        moveContent: true,
      ),
      isNull,
    );
  });

  testWidgets('a detail scrolled down to its comments shows no content', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<VideoExpandContentState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Under the page's bar, as the detail's scroll view.
          appBar: AppBar(),
          body: ListView(
            controller: scroll,
            children: [
              VideoExpandContent(
                key: key,
                child: const SizedBox(height: 200),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      ),
    );
    expect(key.currentState!.debugShowsTop, isTrue);
    // Its bottom stays laid out against the bar, out of sight.
    scroll.jumpTo(150);
    await tester.pump();
    expect(key.currentState!.debugShowsTop, isFalse);
  });

  testWidgets('a list refreshed under the page returns it with no card', (
    tester,
  ) async {
    HotVideoItemModel item(int aid, String title) => .fromJson({
      'aid': aid,
      'cid': aid + 100,
      'bvid': 'BV1xx411c7mD',
      'title': title,
      'pubdate': 0,
      'duration': 60,
      'owner': {'mid': 1, 'name': 'UP'},
      'stat': {'view': 1, 'danmaku': 1},
    });
    final list = ValueNotifier([item(2, '旧视频')]);
    addTearDown(list.dispose);
    await _pump(
      tester,
      // As the list pages build their cards, with no key.
      home: SizedBox(
        width: 400,
        height: 120,
        child: ValueListenableBuilder(
          valueListenable: list,
          builder: (context, items, _) => VideoCardH(videoItem: items[0]),
        ),
      ),
    );
    await tester.tap(find.text('旧视频'));
    await tester.pumpAndSettle();
    expect(find.text('视频页 102'), findsOneWidget);

    list.value = [item(3, '新视频')];
    await tester.pump();
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Another video's card, which the page does not return into.
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('新视频', skipOffstage: false),
                  matching: find.byType(Opacity, skipOffstage: false),
                )
                .first,
          )
          .opacity,
      1,
    );
    await tester.pumpAndSettle();
    expect(find.text('视频页 102'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('falls back to the app transition', () {
    Future<void> expectPlain(WidgetTester tester) async {
      await tester.tap(find.text('卡片'));
      await tester.pumpAndSettle();
      expect(find.text('视频页 3'), findsOneWidget);
      expect(Get.currentRoute, '/videoV');
      expect((Get.arguments as Map)['cid'], 3);
      expect(_expanding(tester), isFalse);
      expect(_cardOpacity(tester), 1);
    }

    testWidgets('with animations turned off', (tester) async {
      await _pump(tester, disableAnimations: true);
      await expectPlain(tester);
    });

    testWidgets('with the switch off', (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.videoExpand, false),
      );
      await _pump(tester);
      await expectPlain(tester);
    });

    testWidgets('on a desktop', (tester) async {
      VideoExpand.debugMobile = false;
      await _pump(tester);
      await expectPlain(tester);
    });

    testWidgets('without a source', (tester) async {
      await _pump(
        tester,
        home: InkWell(
          onTap: () => PageUtils.toVideoPage(
            aid: 2,
            bvid: 'BV1xx411c7mD',
            cid: 3,
          ),
          child: const SizedBox(width: 180, height: 200, child: Text('卡片')),
        ),
      );
      await tester.tap(find.text('卡片'));
      await tester.pumpAndSettle();
      expect(Get.currentRoute, '/videoV');
      expect(_expanding(tester), isFalse);
    });

    testWidgets('when the card is off screen', (tester) async {
      await _pump(
        tester,
        home: Transform.translate(
          offset: const Offset(0, 2000),
          child: _card0(),
        ),
      );
      final source = tester.state<VideoExpandSourceState>(
        find.byType(VideoExpandSource),
      );
      expect(source.expand<void>('/videoV', arguments: const {}), isNull);
    });
  });
}
