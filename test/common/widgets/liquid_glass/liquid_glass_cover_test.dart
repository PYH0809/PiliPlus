// Run both ways: `flutter test` frosts, `flutter test --enable-impeller`
// bends through the shader, which covers the pane's rect under a clip.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 200;
const _height = 120;
const _backdrop = Color(0xFF2050E0);

void main() {
  testWidgets('glass stays inside its rounded corners', (tester) async {
    tester.view
      ..physicalSize = const Size(_width + 0.0, _height + 0.0)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: LiquidGlassScope(
          enabled: true,
          child: LiquidGlassHost(
            enabled: true,
            child: RepaintBoundary(
              key: key,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: _backdrop)),
                  Positioned(
                    left: 20,
                    top: 20,
                    width: 160,
                    height: 80,
                    child: LiquidGlass(
                      style: LiquidGlassStyle.regular(
                        const ColorScheme.light(),
                      ),
                      borderRadius: BorderRadius.circular(40),
                      child: const SizedBox.expand(),
                    ),
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
    tester.binding.scheduleFrame();
    await tester.pump();

    final pixels = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!;
    });
    Color at(ByteData pixels, int x, int y) {
      final i = (y * _width + x) * 4;
      return Color.fromARGB(
        pixels.getUint8(i + 3),
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
    }

    final reason = 'shader filters: ${ui.ImageFilter.isShaderFilterSupported}';
    // Inside the pane's rect, past its corner's curve: the backdrop alone.
    expect(at(pixels!, 23, 23), _backdrop, reason: reason);
    expect(at(pixels, 176, 96), _backdrop, reason: reason);
    // Its middle is glass, lighter than the backdrop under its pale tint.
    expect(at(pixels, 100, 60), isNot(_backdrop), reason: reason);
    expect(
      at(pixels, 100, 60).computeLuminance(),
      greaterThan(_backdrop.computeLuminance()),
      reason: reason,
    );
  });
}
