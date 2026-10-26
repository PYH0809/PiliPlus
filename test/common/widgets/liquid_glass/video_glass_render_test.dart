// Run both ways: `flutter test` frosts, `flutter test --enable-impeller`
// bends through the shader.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
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
  // VideoGlass reads whether to bend through Pref.
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-glass-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

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

  // Headless, Impeller reads a stale backdrop under a pane drawn in a
  // later test, so this one checks the frost; the bend's own style is
  // checked on a device.
  testWidgets(
    'a frosted pane takes the style it is given',
    skip: ui.ImageFilter.isShaderFilterSupported,
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: Colors.black,
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: Center(
                    child: VideoGlass(
                      radius: 24,
                      // A light panel's glass, as over the full-screen video.
                      style: LiquidGlassStyle(
                        tint: Color(0xCCFFFFFF),
                        blur: 30,
                      ),
                      child: SizedBox(width: 160, height: 60),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
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
      // The middle of the pane, over black: light only through its own tint.
      const i = (50 * 200 + 100) * 4;
      expect(
        pixels!.getUint8(i),
        greaterThan(150),
        reason: 'shader filters: ${ui.ImageFilter.isShaderFilterSupported}',
      );
    },
  );

  testWidgets('with refraction off a pane only frosts', (tester) async {
    Future<int> filters({required bool refract}) async {
      // Hive writes real files, outside the test's fake clock.
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.videoGlassRefraction, refract),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          key: ValueKey(refract),
          child: const Center(
            child: VideoGlass.capsule(child: SizedBox(width: 120, height: 36)),
          ),
        ),
      );
      // The shader loads off the frame.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      return tester.layers.whereType<BackdropFilterLayer>().length;
    }

    // Bending stacks the shader's filter on the frost's.
    final bends = ui.ImageFilter.isShaderFilterSupported;
    expect(await filters(refract: true), bends ? 2 : 1);
    expect(await filters(refract: false), 1);
    await tester.runAsync(
      () => GStorage.setting.delete(SettingBoxKey.videoGlassRefraction),
    );
  });
}
