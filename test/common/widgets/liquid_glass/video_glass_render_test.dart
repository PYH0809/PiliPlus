// Run both ways: `flutter test` frosts, `flutter test --enable-impeller`
// bends through the shader.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Stripes standing in for the video.
class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 4, size.height),
        Paint()..color = x % 16 == 0 ? Colors.red : Colors.yellow,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

const _pane = Rect.fromLTWH(40, 70, 220, 60);

double _variance(ByteData pixels, int width, Rect rect) {
  final values = <double>[];
  for (var y = rect.top.toInt(); y < rect.bottom; y++) {
    for (var x = rect.left.toInt(); x < rect.right; x++) {
      final i = (y * width + x) * 4;
      values.add(pixels.getUint8(i) * 0.3 + pixels.getUint8(i + 1) * 0.59);
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  return values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      values.length;
}

void main() {
  testWidgets('the glass softens what lies under it', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 300,
              height: 200,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _Stripes()),
                  ),
                  Positioned.fromRect(
                    rect: _pane,
                    child: const VideoGlass.capsule(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    // Inset from the rim, where the glass bends the most.
    final under = _variance(pixels!, 300, _pane.deflate(16));
    final beside = _variance(
      pixels,
      300,
      const Rect.fromLTWH(40, 150, 220, 40),
    );
    expect(
      under,
      lessThan(beside / 2),
      reason: 'shader filters: ${ui.ImageFilter.isShaderFilterSupported}',
    );
  });
}
