// Run with `flutter test --enable-impeller`: without shader filters the pane
// only frosts, and the test skips.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_panel.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 300;
const _height = 200;

final _boundary = GlobalKey();

double _luminance(Color color) {
  double linear(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

double _contrast(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// The glass of a dark edit menu over [behind], at the pane's middle.
Future<Color> _glassOver(WidgetTester tester, Color behind) async {
  tester.view
    ..physicalSize = const Size(_width + 0.0, _height + 0.0)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final colorScheme = ThemeData(brightness: Brightness.dark).colorScheme;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => LiquidGlassScope(
        enabled: true,
        child: LiquidGlassHost(
          enabled: true,
          child: RepaintBoundary(key: _boundary, child: child),
        ),
      ),
      home: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: behind)),
          Positioned(
            left: 50,
            top: 76,
            width: 200,
            height: 48,
            child: GlassPanel(
              style: LiquidGlassStyle.editMenu(colorScheme),
              radius: 24,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    ),
  );
  tester.binding.scheduleFrame();
  await tester.pump();
  final data = (await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    image.dispose();
    return bytes!;
  }))!;
  const offset = (_height ~/ 2 * _width + _width ~/ 2) * 4;
  return Color.fromARGB(
    255,
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void main() {
  // The text selection toolbar's labels when dark (GlassSurfaces).
  const label = Colors.white;

  for (final (name, behind) in const [
    ('white', Color(0xFFFFFFFF)),
    ('yellow', Color(0xFFFFE070)),
    ('light blue', Color(0xFF80C8FF)),
  ]) {
    testWidgets(
      'a dark edit menu\'s labels read at 4.5:1 or more over $name',
      (tester) async {
        final glass = await _glassOver(tester, behind);
        expect(_contrast(label, glass), greaterThanOrEqualTo(4.5));
      },
      skip: !ui.ImageFilter.isShaderFilterSupported,
    );
  }
}
