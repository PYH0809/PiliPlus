// Run both ways: `flutter test` tints, `flutter test --enable-impeller`
// bends through the shader.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/pages/common/dyn/action_bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Wide enough that the glass bends only the cell's own color.
const _cell = 160;

// Colors that, through thin glass, drown a light icon or a dark one.
const _backdrops = {
  'magenta': Color(0xFFFF00FF),
  'cyan': Color(0xFF00FFFF),
  'yellow': Color(0xFFFFFF00),
  'white': Color(0xFFFFFFFF),
  'black': Color(0xFF000000),
};

Color _pixel(ByteData pixels, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.fromARGB(
    255,
    pixels.getUint8(i),
    pixels.getUint8(i + 1),
    pixels.getUint8(i + 2),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('in ${brightness.name}, the reply icon keeps 3:1 over any '
        'color', (tester) async {
      final colorScheme = ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: brightness,
      );
      final width = _cell * _backdrops.length;
      tester.view
        ..physicalSize = Size(width.toDouble(), _cell.toDouble())
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: colorScheme),
          // As main.dart's builder.
          builder: (context, child) => LiquidGlassScope(
            enabled: true,
            child: LiquidGlassHost(
              enabled: true,
              child: RepaintBoundary(key: key, child: child),
            ),
          ),
          home: Row(
            children: [
              for (final color in _backdrops.values)
                Expanded(
                  child: ColoredBox(
                    color: color,
                    child: Center(child: GlassReplyButton(onTap: () {})),
                  ),
                ),
            ],
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
      final icon = colorScheme.primary;
      const center = _cell ~/ 2;
      var i = 0;
      for (final name in _backdrops.keys) {
        final x = i * _cell + center;
        // The glass either side of the icon, between it and the rim.
        var least = double.infinity;
        for (var y = center - 3; y < center + 3; y++) {
          for (var dx = 15; dx < 21; dx++) {
            least = math.min(
              least,
              math.min(
                _contrast(icon, _pixel(pixels!, width, x - dx, y)),
                _contrast(icon, _pixel(pixels, width, x + dx, y)),
              ),
            );
          }
        }
        expect(
          least,
          greaterThanOrEqualTo(3),
          reason:
              '$name, shader filters: ${ui.ImageFilter.isShaderFilterSupported}',
        );
        i++;
      }
    });
  }
}
