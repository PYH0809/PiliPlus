// Run both ways: `flutter test` tints, `flutter test --enable-impeller`
// bends through the shader.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 412;

// Stripes 1 dp wide standing in for the list under the bar, as fine as text.
class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i * 2 < size.width; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 2.0, 0, 1, size.height),
        Paint()..color = i.isEven ? Colors.red : Colors.yellow,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

double _variance(ByteData pixels, Rect rect) {
  final values = <double>[];
  for (var y = rect.top.toInt(); y < rect.bottom; y++) {
    for (var x = rect.left.toInt(); x < rect.right; x++) {
      final i = (y * _width + x) * 4;
      values.add(pixels.getUint8(i) * 0.3 + pixels.getUint8(i + 1) * 0.59);
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  return values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      values.length;
}

void main() {
  setUp(() => GlassAppBar.debugEnabled = true);
  tearDown(() => GlassAppBar.debugEnabled = null);

  testWidgets('the back circle and the capsule are glass over the list', (
    tester,
  ) async {
    tester.view
      ..physicalSize = Size(_width.toDouble(), 300)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        // As main.dart's builder.
        builder: (context, child) => LiquidGlassScope(
          enabled: true,
          child: LiquidGlassHost(
            enabled: true,
            child: RepaintBoundary(key: key, child: child),
          ),
        ),
        home: const SizedBox(),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => SimpleScaffold(
              appBar: GlassAppBar(
                // Without a glyph, which would read as stripes of its own.
                actions: [
                  IconButton(onPressed: () {}, icon: const SizedBox()),
                ],
              ),
              body: const SizedBox.expand(
                child: CustomPaint(painter: _Stripes()),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
    // The shader loads off the frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final pixels = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!;
    });
    // The bar's row runs from 24 to 80, its buttons from 30 to 74.
    // The back circle, above its arrow.
    final back = _variance(pixels!, const Rect.fromLTWH(26, 34, 20, 6));
    final capsule = _variance(pixels, const Rect.fromLTWH(364, 40, 24, 24));
    // Between them, the list under the fade alone, faint behind the title
    // but there.
    final fade = _variance(pixels, const Rect.fromLTWH(120, 40, 60, 24));
    final open = _variance(pixels, const Rect.fromLTWH(120, 200, 60, 24));
    final reason = 'shader filters: ${ui.ImageFilter.isShaderFilterSupported}';
    expect(fade, lessThan(open / 20), reason: reason);
    expect(fade, greaterThan(open / 1000), reason: reason);
    expect(back, lessThan(fade / 20), reason: reason);
    expect(capsule, lessThan(fade / 20), reason: reason);
  });
}
