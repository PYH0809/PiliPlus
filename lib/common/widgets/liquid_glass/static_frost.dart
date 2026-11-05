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
/// the sheet's whole time open; its glass reads no scrim and bends nothing.
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
      tint: switch (LiquidGlassStyle.menu(colorScheme).tint) {
        final tint when image == null => tint.withValues(
          alpha: (tint.a + 0.3).clamp(0.0, 1.0),
        ),
        final tint => tint,
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

  /// Texels a logical pixel the page is taken at: the blur hides more.
  static const _texelsPerDp = 0.5;

  /// The page under [below] as it last composited, at a few texels a dp,
  /// blurred and its colors livened as the menus' glass livens them, into an
  /// image of its own. Taken in the tap that opens the sheet, outside any
  /// frame; both pictures are drawn on the raster thread, ahead of the
  /// sheet's first frame, which shows it offstage.
  static StaticFrostPicture? take(
    ModalRoute<dynamic>? below,
    ColorScheme colorScheme,
    Size screen,
  ) {
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
    final sigma = style.blur * _texelsPerDp;
    final recorder = ui.PictureRecorder();
    final texels =
        Offset.zero & Size(page.width.toDouble(), page.height.toDouble());
    // Filtered through a layer: a filter on the image's own paint went
    // unheeded on Impeller.
    Canvas(recorder)
      ..saveLayer(
        texels,
        Paint()
          ..imageFilter = ui.ImageFilter.compose(
            outer: ui.ColorFilter.matrix(_livelier(style.saturation)),
            inner: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.clamp,
            ),
          ),
      )
      ..drawImage(page, Offset.zero, Paint())
      ..restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(page.width, page.height);
    picture.dispose();
    page.dispose();
    return StaticFrostPicture._(
      image,
      boundary.localToGlobal(Offset.zero) & size,
      screen,
      colorScheme.brightness,
    );
  }
}

// Saturation as a matrix that keeps luminance.
List<double> _livelier(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r + (1 - r) * s,
    g * (1 - s),
    b * (1 - s),
    0,
    0,
    r * (1 - s),
    g + (1 - g) * s,
    b * (1 - s),
    0,
    0,
    r * (1 - s),
    g * (1 - s),
    b + (1 - b) * s,
    0,
    0,
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
            Paint()..filterQuality = FilterQuality.low,
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
