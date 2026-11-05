import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// A sheet's glass drawn from one picture of the page under it ([picture],
/// taken as the sheet sets off to open), blurred once and laid where the
/// page lies on screen, with the menus' tint over it. The sheet's route owns
/// the picture: it outlives this pane, which goes and comes back as the
/// screen turns.
///
/// Live glass, which the host captures again whenever what lies under it
/// changes, took a phone's raster thread 12–17 ms a frame as a sheet half
/// the screen tall slid up over its fading scrim: the pane moved, the scrim
/// changed, and the host blurred the whole of it again each frame. The page
/// under a sheet holds still behind its scrim, so one picture of it serves
/// the sheet's whole time open, the scrim baked in as it will stand; its
/// glass bends nothing.
/// A page the picture no longer shows, as the screen turned or the theme
/// changed, leaves only the tint.
class StaticFrost extends StatelessWidget {
  const StaticFrost({
    super.key,
    required this.picture,
    required this.radius,
    required this.child,
  });

  final StaticFrostPicture? picture;

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final dark = colorScheme.brightness == Brightness.dark;
    final picture = this.picture;
    // A page the picture no longer shows leaves only the tint.
    if (picture != null &&
        (MediaQuery.sizeOf(context) != picture.screen ||
            colorScheme.brightness != picture.brightness)) {
      picture.drop();
    }
    final image = picture?.image;
    return _StaticFrostPane(
      image: image,
      rect: picture?.rect,
      // The route slides the sheet by a layer's transform, painting nothing
      // again: the pane follows its every frame, to lie still on screen.
      moves: ModalRoute.of(context)?.animation,
      radius: radius,
      // Without the picture the tint thickens, as glass's does with no
      // backdrop to read.
      // Without the picture the tint thickens, as glass's does with no
      // backdrop to read; dark, a little in any case, for its white text.
      tint: switch (LiquidGlassStyle.menu(colorScheme).tint) {
        final tint => tint.withValues(
          alpha: (tint.a + (image == null ? 0.3 : 0) + (dark ? 0.08 : 0)).clamp(
            0.0,
            1.0,
          ),
        ),
      },
      rim: Colors.white.withValues(alpha: dark ? 0.16 : 0.5),
      // Its content paints apart from it, once.
      child: RepaintBoundary(child: child),
    );
  }
}

/// The page under a sheet, blurred, where it lies on screen, and the screen
/// and theme it was taken in.
class StaticFrostPicture {
  StaticFrostPicture._(this._image, this.rect, this.screen, this.brightness);

  ui.Image? _image;
  final Rect rect;
  final Size screen;
  final Brightness brightness;

  /// The picture, till [drop] lets it go.
  ui.Image? get image => _image;

  void drop() {
    _image?.dispose();
    _image = null;
  }

  /// Texels a logical pixel the page is taken at, and its frost drawn from.
  static const _texelsPerDp = 1.5;

  /// The page under [below] as it last composited, at a texel and a half a
  /// dp, blurred and its colors livened as the menus' glass livens them, into an
  /// image of its own. Taken in the tap that opens the sheet, outside any
  /// frame; its pictures are drawn on the raster thread, ahead of the
  /// sheet's first frame, which shows it offstage.
  static StaticFrostPicture? take(
    ModalRoute<dynamic>? below,
    ColorScheme colorScheme,
    Size screen, {
    Color scrim = const Color(0x00000000),
  }) {
    final style = LiquidGlassStyle.menu(colorScheme);
    final boundary = below?.subtreeContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.attached ||
        !boundary.hasSize) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer || !layer.supportsRasterization()) {
      return null;
    }
    final size = boundary.size;
    final page = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _texelsPerDp,
    );
    // Halved again and again, each texel the mean of four, till a texel is
    // about as wide as the menus' frost, then doubled back up, each step
    // read between texels: a smooth blur, a pass a step, each smaller than
    // the last. Impeller's own blur of a sigma this wide draws a few
    // texels' squares, which the screen's scale-up showed as steps.
    final levels = <ui.Image>[page];
    var texelsPerDp = _texelsPerDp;
    while (1 / texelsPerDp < style.blur * 3.2 &&
        levels.last.width > 8 &&
        levels.last.height > 8) {
      final last = levels.last;
      levels.add(_scaled(last, last.width ~/ 2, last.height ~/ 2));
      texelsPerDp /= 2;
    }
    var image = levels.removeLast();
    while (levels.length > 1) {
      final next = levels.removeLast();
      final up = _scaled(image, next.width, next.height);
      image.dispose();
      next.dispose();
      image = up;
    }
    // The last step livens the colors, at the size it is drawn from, as the
    // menus' glass does; a low-resolution image livened would show its
    // steps the more. It brightens as live glass does, and darkens again by
    // as much as a dark tint thickens over light content (a negative
    // contrast), so that white text still reads over a bright picture:
    // the frost under the tint then comes out as live glass's over white,
    // and as it over black.
    final full = levels.single;
    // Live glass reads the sheet's scrim over the page, which it then
    // livens and brightens, and its tint thickens over what reads lighter
    // than it by as far as the style's contrast says: the picture, taken
    // before the scrim showed, takes it in here, and the gain darkens it by
    // as much as live glass's tint thickens over white under the scrim.
    final tint = style.tint;
    double luma(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    final behind = 1 - scrim.a * (1 - luma(scrim));
    final clash = ((style.contrast.sign * (luma(tint) - behind) - 0.3) / 0.5)
        .clamp(
          0.0,
          1.0,
        );
    final cover = tint.a + (1 - tint.a) * clash * style.contrast.abs();
    final livened = _scaled(
      image,
      full.width,
      full.height,
      // Lighter than live glass's in light, which over a bright cover,
      // free of the bend and rim that break it up, read as a garish patch.
      saturation: colorScheme.brightness == Brightness.light
          ? math.min(style.saturation, 1.4)
          : style.saturation,
      gain: style.brightness * (1 - cover) / (1 - tint.a),
      scrim: scrim,
    );
    if (!identical(image, full)) image.dispose();
    full.dispose();
    image = livened;
    return StaticFrostPicture._(
      image,
      boundary.localToGlobal(Offset.zero) & size,
      screen,
      colorScheme.brightness,
    );
  }
}

// [image] drawn into an image of [width] by [height], read between its
// texels, its colors livened by [saturation] and scaled by [gain] if given.
ui.Image _scaled(
  ui.Image image,
  int width,
  int height, {
  double? saturation,
  double gain = 1,
  Color scrim = const Color(0x00000000),
}) {
  final recorder = ui.PictureRecorder();
  final paint = Paint()..filterQuality = FilterQuality.low;
  if (saturation != null) {
    paint.colorFilter = ColorFilter.matrix(
      _livelier(saturation, gain, scrim),
    );
  }
  Canvas(recorder).drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    Offset.zero & Size(width.toDouble(), height.toDouble()),
    paint,
  );
  final picture = recorder.endRecording();
  final scaled = picture.toImageSync(width, height);
  picture.dispose();
  return scaled;
}

// Saturation as a matrix that keeps luminance, under [scrim] laid over it,
// then a gain.
List<double> _livelier(double s, double gain, Color scrim) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final k = gain * (1 - scrim.a);
  final lift = gain * scrim.a * 255;
  return [
    k * (r + (1 - r) * s),
    k * g * (1 - s),
    k * b * (1 - s),
    0,
    lift * scrim.r,
    k * r * (1 - s),
    k * (g + (1 - g) * s),
    k * b * (1 - s),
    0,
    lift * scrim.g,
    k * r * (1 - s),
    k * g * (1 - s),
    k * (b + (1 - b) * s),
    0,
    lift * scrim.b,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _StaticFrostPane extends SingleChildRenderObjectWidget {
  const _StaticFrostPane({
    required this.image,
    required this.rect,
    required this.moves,
    required this.radius,
    required this.tint,
    required this.rim,
    super.child,
  });

  final ui.Image? image;
  final Rect? rect;
  final Listenable? moves;
  final double radius;
  final Color tint;
  final Color rim;

  @override
  _RenderStaticFrost createRenderObject(BuildContext context) =>
      _RenderStaticFrost(image, rect, moves, radius, tint, rim);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStaticFrost renderObject,
  ) {
    renderObject
      ..image = image
      ..rect = rect
      ..moves = moves
      ..radius = radius
      ..tint = tint
      ..rim = rim;
  }
}

class _RenderStaticFrost extends RenderProxyBox {
  _RenderStaticFrost(
    this._image,
    this._rect,
    this._moves,
    this._radius,
    this._tint,
    this._rim,
  );

  ui.Image? _image;
  set image(ui.Image? value) {
    if (identical(_image, value)) return;
    _image = value;
    markNeedsPaint();
  }

  Rect? _rect;
  set rect(Rect? value) {
    if (_rect == value) return;
    _rect = value;
    markNeedsPaint();
  }

  Listenable? _moves;
  set moves(Listenable? value) {
    if (identical(_moves, value)) return;
    if (attached) {
      _moves?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _moves = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moves?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moves?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  double _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  Color _tint;
  set tint(Color value) {
    if (_tint == value) return;
    _tint = value;
    markNeedsPaint();
  }

  Color _rim;
  set rim(Color value) {
    if (_rim == value) return;
    _rim = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipRSuperellipseLayer>();

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = Offset.zero & size;
    final shape = BorderRadius.circular(_radius).toRSuperellipse(bounds);
    _clip.layer = context.pushClipRSuperellipse(
      needsCompositing,
      offset,
      bounds,
      shape,
      (context, offset) {
        final canvas = context.canvas;
        final image = _image;
        final rect = _rect;
        if (image != null && rect != null) {
          // Where the page lies on screen, wherever the sheet stands as it
          // slides: the glass shows what is under it.
          final global = localToGlobal(Offset.zero);
          canvas.drawImageRect(
            image,
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
            rect.shift(offset - global),
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
        canvas.drawRect(offset & size, Paint()..color = _tint);
        super.paint(context, offset);
      },
      oldLayer: _clip.layer,
    );
    // The edge, catching light as glass's rim does.
    context.canvas.drawRSuperellipse(
      BorderRadius.circular(
        _radius,
      ).toRSuperellipse((offset & size).deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _rim,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
