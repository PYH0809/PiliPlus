import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/video_card/video_expand.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
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
    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: 225,
            child: VideoExpandTarget(
              watchVideo: watchVideo ?? (shown) => () {},
            ),
          ),
          Text('视频页 ${arguments['cid']}'),
        ],
      ),
    );
  }
}

late ui.Image _coverImage;

Widget _card0({ValueChanged<VideoExpandSourceState>? onSource}) =>
    VideoExpandSource(
      color: Colors.white,
      builder: (context, source) {
        onSource?.call(source);
        return SizedBox(
          width: 180,
          height: 200,
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
                  RawImage(image: _coverImage, width: 180, height: 112.5),
                ),
                const Text('卡片'),
              ],
            ),
          ),
        );
      },
    );

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

    test('a return that interrupted the opening runs it back linearly', () {
      final back = _at(0.5, returning: true, interrupted: true);
      _expectRect(back.rect, Rect.lerp(_card, _screen, 0.5)!);
      expect(back.pageOpacity, moreOrLessEquals(_at(0.5).pageOpacity));
      expect(back.cardOpacity, _at(0.5).cardOpacity);
      expect(back.scrim, _at(0.5).scrim);
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
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('视频页 3'), findsOneWidget);
    expect(await repaintsBelow(), isFalse);

    await tester.pumpAndSettle();
    expect(find.text('视频页 3'), findsNothing);
    expect(await repaintsBelow(), isTrue);
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
    expect(cover, findsOneWidget);

    shown!();
    expect(stopped, isTrue);
    await tester.pumpAndSettle();
    expect(cover, findsNothing);
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
