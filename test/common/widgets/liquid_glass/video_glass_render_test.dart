// Run both ways: `flutter test` frosts, `flutter test --enable-impeller`
// bends through the shader.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/models/common/video_glass_mode.dart';
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

  testWidgets('each mode filters less than the one above it', (
    tester,
  ) async {
    Future<int> filters(
      VideoGlassMode mode, {
      bool notes = true,
      bool note = false,
    }) async {
      // Hive writes real files, outside the test's fake clock.
      await tester.runAsync(() async {
        await GStorage.setting.put(SettingBoxKey.videoGlassMode, mode.index);
        await GStorage.setting.put(SettingBoxKey.videoGlassNotes, notes);
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          key: ValueKey((mode, notes, note)),
          child: Center(
            child: VideoGlass.capsule(
              note: note,
              child: const SizedBox(width: 120, height: 36),
            ),
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
    expect(await filters(VideoGlassMode.refract), bends ? 2 : 1);
    expect(await filters(VideoGlassMode.frost), 1);
    expect(await filters(VideoGlassMode.tint), 0);
    // With notes off a note only tints, and a bar keeps its mode.
    expect(await filters(VideoGlassMode.frost, notes: false, note: true), 0);
    expect(await filters(VideoGlassMode.frost, notes: false), 1);
    await tester.runAsync(() async {
      await GStorage.setting.delete(SettingBoxKey.videoGlassMode);
      await GStorage.setting.delete(SettingBoxKey.videoGlassNotes);
    });
  });

  testWidgets('over the video a pane draws its texture again, not the screen', (
    tester,
  ) async {
    final video = GlobalKey();
    Future<List<Layer>> layers(
      VideoGlassMode mode, {
      bool texture = true,
    }) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.videoGlassMode, mode.index),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          key: ValueKey((mode, texture)),
          child: VideoGlassSource(
            video: video,
            child: Stack(
              children: [
                RepaintBoundary(
                  key: video,
                  child: SizedBox(
                    width: 300,
                    height: 200,
                    child: texture ? const Texture(textureId: 7) : null,
                  ),
                ),
                const Positioned(
                  left: 40,
                  top: 140,
                  width: 220,
                  height: 48,
                  child: VideoGlass(radius: 20),
                ),
              ],
            ),
          ),
        ),
      );
      // The shader loads off the frame.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      return tester.layers;
    }

    int count<T extends Layer>(List<Layer> layers) =>
        layers.whereType<T>().length;

    final bends = ui.ImageFilter.isShaderFilterSupported;
    for (final mode in [VideoGlassMode.refract, VideoGlassMode.frost]) {
      final drawn = await layers(mode);
      expect(count<BackdropFilterLayer>(drawn), 0, reason: '$mode');
      // The video's own texture, and the pane's copy of it.
      expect(count<TextureLayer>(drawn), 2, reason: '$mode');
      // Frosting, a blur; bending, the shader, which frosts as it samples,
      // and past two texels a dp, as the test's 3, a matrix filter that
      // draws the bend up.
      final dpr = tester.view.devicePixelRatio;
      expect(
        count<ImageFilterLayer>(drawn),
        mode == VideoGlassMode.refract && bends && dpr > 2 ? 2 : 1,
        reason: '$mode',
      );
    }
    // Till the video's texture shows, only the tint.
    final loading = await layers(VideoGlassMode.frost, texture: false);
    expect(count<BackdropFilterLayer>(loading), 0);
    expect(count<ImageFilterLayer>(loading), 0);
    await tester.runAsync(
      () => GStorage.setting.delete(SettingBoxKey.videoGlassMode),
    );
  });

  testWidgets('a pane follows the video to a new texture', (tester) async {
    final video = GlobalKey();
    final changes = ValueNotifier(7);
    addTearDown(changes.dispose);
    Widget player() => Directionality(
      textDirection: TextDirection.ltr,
      child: VideoGlassSource(
        video: video,
        changes: changes,
        child: Stack(
          children: [
            RepaintBoundary(
              key: video,
              child: SizedBox(
                width: 300,
                height: 200,
                child: ValueListenableBuilder(
                  valueListenable: changes,
                  builder: (context, texture, _) => Texture(textureId: texture),
                ),
              ),
            ),
            const Positioned(
              left: 40,
              top: 140,
              width: 220,
              height: 48,
              child: VideoGlass(radius: 20),
            ),
          ],
        ),
      ),
    );
    Set<int> textures() => {
      for (final layer in tester.layers.whereType<TextureLayer>())
        layer.textureId,
    };

    await tester.runAsync(
      () => GStorage.setting.put(
        SettingBoxKey.videoGlassMode,
        VideoGlassMode.frost.index,
      ),
    );
    await tester.pumpWidget(player());
    await tester.pump();
    expect(textures(), {7});
    // The copy a glass host would replay for nothing, it leaves out.
    expect(tester.layers.whereType<LiquidGlassUnseenLayer>(), hasLength(1));

    // As the screen turns, hardware decoding outputs to a texture anew.
    changes.value = 8;
    await tester.pump();
    expect(textures(), {8});
    await tester.runAsync(
      () => GStorage.setting.delete(SettingBoxKey.videoGlassMode),
    );
  });

  testWidgets('the copy lies where the video shows, scaled and offset', (
    tester,
  ) async {
    final video = GlobalKey();
    await tester.runAsync(
      () => GStorage.setting.put(
        SettingBoxKey.videoGlassMode,
        VideoGlassMode.frost.index,
      ),
    );
    // As the player fits a video, scaled up and centered: a cousin of the
    // pane, not its ancestor.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: VideoGlassSource(
          video: video,
          child: Stack(
            children: [
              Positioned(
                left: 10,
                top: 0,
                child: Transform.scale(
                  scale: 2,
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: video,
                    child: const SizedBox(
                      width: 150,
                      height: 100,
                      child: Texture(textureId: 7),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 40,
                top: 140,
                width: 220,
                height: 48,
                child: VideoGlass(radius: 20),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final unseen = tester.layers.whereType<LiquidGlassUnseenLayer>().single;
    TextureLayer? copy;
    Matrix4 placed = Matrix4.identity();
    void find(Layer layer, Matrix4 at) {
      if (layer is TextureLayer) {
        copy = layer;
        placed = at;
        return;
      }
      if (layer is ContainerLayer) {
        final inner = at.clone();
        if (layer is TransformLayer) inner.multiply(layer.transform!);
        if (layer is OffsetLayer) {
          inner.translateByDouble(layer.offset.dx, layer.offset.dy, 0, 1);
        }
        for (Layer? child = layer.firstChild; child != null;) {
          find(child, inner);
          child = child.nextSibling;
        }
      }
    }

    find(unseen, Matrix4.identity());
    expect(copy, isNotNull);
    // On screen, the copy covers the video: from (10, 0), 300 by 200.
    final shown = MatrixUtils.transformRect(placed, copy!.rect);
    expect(shown.left, moreOrLessEquals(10));
    expect(shown.top, moreOrLessEquals(0));
    expect(shown.width, moreOrLessEquals(300));
    expect(shown.height, moreOrLessEquals(200));
    await tester.runAsync(
      () => GStorage.setting.delete(SettingBoxKey.videoGlassMode),
    );
  });
}
