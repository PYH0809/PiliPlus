import 'dart:convert';
import 'dart:developer' as developer;

import 'package:PiliPlus/common/widgets/frame_stats.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/pages/audio/backdrop/audio_backdrop.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

/// Commands for driving the app from a computer while testing on a device,
/// as VM service extensions: absent from release builds, which have no VM
/// service. Call them on the URL `flutter run` prints, as
/// `<url>ext.piliplus.setting?key=videoGlassMode&value=1`.
///
/// - `ext.piliplus.setting?key=&value=`: puts a setting, `value` as JSON
///   (`1`, `true`, `"text"`) or a bare string; most take effect as the page
///   they are read in opens again.
/// - `ext.piliplus.open?url=`: opens a link, as one tapped in the app.
/// - `ext.piliplus.fullscreen?on=`: turns the open player full screen or
///   back.
/// - `ext.piliplus.controls?on=`: shows or hides the open player's controls.
/// - `ext.piliplus.play`: plays the open player.
/// - `ext.piliplus.state`: the open player's state, the frames the
///   performance overlay counted and what the glass over the video drew.
/// - `ext.piliplus.resetFrames`: starts the overlay's count over.
/// - `ext.piliplus.layers`: the layer tree the screen last drew, a layer a
///   line with what it clips, filters, offsets or draws, to tell what each
///   offscreen pass holds.
/// - `ext.piliplus.audioBackdropFps?value=`: how often 听视频's background
///   moves, to measure what the glass over it costs at each rate; no value
///   for the default.
/// - `ext.piliplus.glassImages?on=`: whether glass draws its shadows and
///   its frost's rims from images, `true` or `false`; no value for
///   the renderer's choice, only without Impeller. Everything repaints.
/// - `ext.piliplus.frames?seconds=`: draws a frame every vsync for that long,
///   though nothing changed, and answers once done: the overlay then counts
///   what the screen costs a frame, as a video's every new frame redraws it,
///   which the overlay does not see.
abstract final class DebugCommands {
  static void register() {
    if (kReleaseMode) return;
    _register('setting', (params) async {
      final key = params['key'];
      final raw = params['value'];
      if (key == null || raw == null) return 'needs key and value';
      Object? value;
      try {
        value = jsonDecode(raw);
      } on FormatException {
        value = raw;
      }
      await GStorage.setting.put(key, value);
      return '$key = $value';
    });
    _register('audioBackdropFps', (params) async {
      final fps = int.tryParse(params['value'] ?? '');
      AudioBackdrop.debugFps.value = fps;
      return '${AudioBackdrop.currentFps}';
    });
    _register('glassImages', (params) async {
      LiquidGlassHost.debugImagesOverride = switch (params['on']) {
        'true' => true,
        'false' => false,
        _ => null,
      };
      void repaint(RenderObject object) {
        object
          ..markNeedsPaint()
          ..visitChildren(repaint);
      }

      RendererBinding.instance.renderViews.forEach(repaint);
      return '${LiquidGlassHost.debugImagesOverride}';
    });
    _register('open', (params) async {
      final url = params['url'];
      if (url == null) return 'needs url';
      return '${await PiliScheme.routePushFromUrl(url)}';
    });
    _register('fullscreen', (params) async {
      final player = PlPlayerController.instance;
      if (player == null) return 'no player';
      await player.triggerFullScreen(status: params['on'] != 'false');
      return '${player.isFullScreen.value}';
    });
    _register('controls', (params) async {
      final player = PlPlayerController.instance;
      if (player == null) return 'no player';
      player.controls = params['on'] != 'false';
      return '${player.showControls.value}';
    });
    _register('play', (params) async {
      final player = PlPlayerController.instance;
      if (player == null) return 'no player';
      await player.play(hideControls: false);
      return '${player.playerStatus.isPlaying}';
    });
    _register('state', (params) async {
      final player = PlPlayerController.instance;
      return jsonEncode({
        'route': Get.currentRoute,
        'player': player != null,
        'playing': player?.playerStatus.isPlaying,
        'position': player?.position.value,
        'fullscreen': player?.isFullScreen.value,
        'controls': player?.showControls.value,
        'frames': FrameStats.measure(),
        'glass': VideoGlass.debugInfo.value,
      });
    });
    _register('layers', (params) async {
      final view = RendererBinding.instance.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final root = view.layer;
      if (root == null) return 'no layers';
      final lines = <String>[];
      void walk(Layer layer, int depth) {
        lines.add('${'  ' * depth}${_describeLayer(layer)}');
        if (layer is ContainerLayer) {
          for (Layer? child = layer.firstChild; child != null;) {
            walk(child, depth + 1);
            child = child.nextSibling;
          }
        }
      }

      walk(root, 0);
      return lines.join('\n');
    });
    _register('resetFrames', (params) async {
      FrameStats.reset();
      return 'ok';
    });
    _register('frameLog', (params) async => jsonEncode(FrameStats.log()));
    _register('frames', (params) async {
      final seconds = double.tryParse(params['seconds'] ?? '') ?? 3;
      final ticker = Ticker((_) {})..start();
      await Future<void>.delayed(
        Duration(milliseconds: (seconds * 1000).round()),
      );
      ticker.dispose();
      return 'ok';
    });
  }

  static String _describeLayer(Layer layer) {
    String rect(Rect r) =>
        '${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} '
        '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}';
    final name = layer.runtimeType.toString();
    return switch (layer) {
      PictureLayer(:final canvasBounds) => '$name ${rect(canvasBounds)}',
      TextureLayer(:final rect, :final textureId) =>
        '$name #$textureId ${rect.toString()}',
      ClipRectLayer(:final clipRect?) => '$name ${rect(clipRect)}',
      ClipRRectLayer(:final clipRRect?) => '$name ${rect(clipRRect.outerRect)}',
      ClipRSuperellipseLayer(:final clipRSuperellipse?) =>
        '$name ${rect(clipRSuperellipse.outerRect)}',
      ClipPathLayer(:final clipPath?) => '$name ${rect(clipPath.getBounds())}',
      ImageFilterLayer(:final imageFilter) =>
        '$name ${imageFilter.runtimeType} ${'$imageFilter'.split('(').first}',
      BackdropFilterLayer(:final filter) =>
        '$name ${'$filter'.split('(').first}',
      OpacityLayer(:final alpha, :final offset) => '$name a=$alpha @$offset',
      ColorFilterLayer() => name,
      ShaderMaskLayer() => name,
      TransformLayer(:final transform?) =>
        '$name t=${transform.getTranslation().x.toStringAsFixed(0)},'
            '${transform.getTranslation().y.toStringAsFixed(0)} '
            's=${transform.storage[0].toStringAsFixed(2)}',
      OffsetLayer(:final offset) => '$name @$offset',
      _ => name,
    };
  }

  static void _register(
    String name,
    Future<String> Function(Map<String, String> params) run,
  ) {
    developer.registerExtension('ext.piliplus.$name', (method, params) async {
      try {
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'result': await run(params)}),
        );
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$e',
        );
      }
    });
  }
}
