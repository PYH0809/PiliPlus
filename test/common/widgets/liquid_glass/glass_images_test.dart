// Run both ways: `flutter test` draws a pane's shadows and frost from
// images on its own, `flutter test --enable-impeller` only when told to.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 300;
const _height = 200;

// Stripes 1 dp wide under the pane, as fine as text.
class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    for (var i = 0; i * 2 < size.width; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 2.0, 0, 1, size.height),
        Paint()..color = i.isEven ? Colors.indigo : Colors.amber,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

final _boundary = GlobalKey();

/// A pill with shadows over stripes, [left] off a whole pixel, as layout
/// leaves panes.
Widget _app({double left = 40.5, Brightness brightness = Brightness.light}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
  );
  return MaterialApp(
    builder: (context, child) => LiquidGlassScope(
      enabled: true,
      child: LiquidGlassHost(
        enabled: true,
        child: RepaintBoundary(key: _boundary, child: child),
      ),
    ),
    home: Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _Stripes())),
        Positioned(
          left: left,
          top: 60.25,
          width: 200,
          height: 48,
          child: LiquidGlass(
            style: LiquidGlassStyle.regular(colorScheme),
            shadows: floatingGlassShadows(colorScheme),
          ),
        ),
      ],
    ),
  );
}

/// Draws a frame though nothing changed: the host captures again.
Future<void> _frame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

/// The largest difference of a channel between [a] and [b].
int _largestDifference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = (a[i] - b[i]).abs();
    if (difference > largest) {
      largest = difference;
    }
  }
  return largest;
}

/// A view [_width] by [_height], a pixel a dp, so that the device's pixels
/// are the image's.
void _view(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(_width + 0.0, _height + 0.0)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  tearDown(() => LiquidGlassHost.debugImagesOverride = null);

  testWidgets('a still pane draws its shadows and frost from images, only '
      'without Impeller', (tester) async {
    _view(tester);
    final before = LiquidGlassHost.debugDeviceImages;
    await tester.pumpWidget(_app());
    // The first frame draws the paths; the second asks for the same, and
    // they go to images.
    await _frame(tester);
    final images = LiquidGlassHost.debugDeviceImages - before;
    expect(
      images,
      ui.ImageFilter.isShaderFilterSupported ? 0 : 2,
      reason: 'shader filters: ${ui.ImageFilter.isShaderFilterSupported}',
    );

    await tester.pumpWidget(const SizedBox());
    expect(LiquidGlassHost.debugDeviceImages, before);
  });

  testWidgets('a pane on the move keeps to its paths, and goes to images '
      'once it holds still', (tester) async {
    _view(tester);
    LiquidGlassHost.debugImagesOverride = true;
    final before = LiquidGlassHost.debugDeviceImages;
    for (var step = 0; step < 6; step++) {
      await tester.pumpWidget(_app(left: 40 + step * 0.3));
      expect(LiquidGlassHost.debugDeviceImages, before, reason: 'step $step');
    }
    await _frame(tester);
    expect(LiquidGlassHost.debugDeviceImages, greaterThan(before));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'drawn from images, the glass looks as drawn from paths, '
      '${brightness.name}',
      (tester) async {
        _view(tester);
        LiquidGlassHost.debugImagesOverride = true;
        await tester.pumpWidget(_app(brightness: brightness));
        // Moved a little and back: the first frame back draws the paths.
        await tester.pumpWidget(_app(left: 41, brightness: brightness));
        await tester.pumpWidget(_app(brightness: brightness));
        final paths = await _pixels(tester);
        final images = LiquidGlassHost.debugDeviceImages;
        await _frame(tester);
        expect(LiquidGlassHost.debugDeviceImages, greaterThan(images));
        final copied = await _pixels(tester);
        // The rims, drawn into an image and then over the glass, round twice
        // to eight bits.
        expect(_largestDifference(paths, copied), lessThanOrEqualTo(2));
      },
      // Only Skia draws from images. Impeller's image of a shadow would cut
      // it off its pane without the anti-aliasing it draws on screen.
      skip: ui.ImageFilter.isShaderFilterSupported,
    );
  }
}
