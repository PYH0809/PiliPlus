part of 'liquid_glass.dart';

// PiliPlus: not from FlClash. Without Impeller, a pane's shadows and the tint
// and rims of its frost are drawn from images, as their paths cost Skia far
// more than copying them: Flutter hands Skia a new path every frame, so Skia
// masks and blurs every shadow and strokes every rim again. On a OnePlus 7
// Pro they took 8 ms of a 17 ms frame over 听视频's moving background.

/// Whether panes draw what holds still from images: only without Impeller,
/// which draws the paths as cheaply as it would copy them.
bool get _drawsFromImages =>
    LiquidGlassHost.debugImagesOverride ??
    !ui.ImageFilter.isShaderFilterSupported;

/// Images larger than this many pixels a side are left to the paths.
const int _maxImageSide = 4096;

/// What a pane draws the same frame after frame, drawn once into an image
/// that lies on whole device pixels, so that copying it changes no pixel.
class _DeviceImage {
  static int _live = 0;
  static int _made = 0;

  ui.Image? _image;

  /// What [_image] shows, and what the pass before asked for.
  Object? _key;
  Object? _asked;

  /// Where [_image] lies, in what it was drawn in.
  Rect _rect = Rect.zero;

  ui.Image? get image => _image;

  /// Readies [paint]'s drawing of [bounds], which [toDevice] puts on the
  /// screen, as an image, once two passes in a row ask for the same: a pane
  /// on the move keeps drawing its paths rather than an image each frame.
  /// Answers whether the image is ready to [draw].
  bool update(
    Rect bounds,
    Matrix4 toDevice,
    Object key,
    void Function(Canvas canvas) paint,
  ) {
    final m = toDevice.storage;
    if (m[1] != 0 ||
        m[4] != 0 ||
        m[3] != 0 ||
        m[7] != 0 ||
        m[15] != 1 ||
        m[0] <= 0 ||
        m[5] <= 0) {
      _asked = null;
      return false;
    }
    final left = bounds.left * m[0] + m[12];
    final top = bounds.top * m[5] + m[13];
    final x = left.floorToDouble();
    final y = top.floorToDouble();
    final width = (bounds.right * m[0] + m[12]).ceil() - x.toInt();
    final height = (bounds.bottom * m[5] + m[13]).ceil() - y.toInt();
    if (width <= 0 ||
        height <= 0 ||
        width > _maxImageSide ||
        height > _maxImageSide) {
      _asked = null;
      return false;
    }
    final asked = (key, m[0], m[5], left - x, top - y, width, height);
    if (_image != null && asked == _key) {
      // Else, between two places, the one not held would look asked twice.
      _asked = asked;
      return true;
    }
    if (asked != _asked) {
      _asked = asked;
      return false;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..translate(-x, -y)
      ..transform(m);
    paint(canvas);
    final picture = recorder.endRecording();
    clear();
    _image = picture.toImageSync(width, height);
    _live++;
    _made++;
    picture.dispose();
    _key = asked;
    _rect = Rect.fromLTRB(
      (x - m[12]) / m[0],
      (y - m[13]) / m[5],
      (x + width - m[12]) / m[0],
      (y + height - m[13]) / m[5],
    );
    return true;
  }

  /// Draws the image, one of its pixels on each of the device's.
  void draw(Canvas canvas) {
    final image = _image!;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _rect,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  void clear() {
    if (_image != null) {
      _image!.dispose();
      _image = null;
      _live--;
    }
    _key = null;
  }
}

/// A pane's shadows in a layer of their own, just where they were painted,
/// so that the host can lay them on the device's pixels and they draw from
/// an image ([_DeviceImage]) while the pane holds still.
class _LiquidGlassShadowLayer extends Layer {
  ui.Picture? _paths;
  (Rect, BorderRadius)? _pathsKey;
  List<BoxShadow> _shadows = const [];
  Rect _bounds = Rect.zero;

  final _image = _DeviceImage();
  ui.Picture? _copy;
  ui.Image? _copied;

  /// The host's pass that found the image ready, where it lays the shadows.
  int _readyPass = -1;

  /// Records [record]'s [shadows] of [rect], which reach [bounds], unless
  /// they are those it holds.
  void paint(
    Rect rect,
    BorderRadius corners,
    List<BoxShadow> shadows,
    Rect bounds,
    void Function(Canvas, Rect, BorderRadius, List<BoxShadow>) record,
  ) {
    final key = (rect, corners);
    if (_paths != null && key == _pathsKey && listEquals(shadows, _shadows)) {
      return;
    }
    final recorder = ui.PictureRecorder();
    record(Canvas(recorder), rect, corners, shadows);
    _paths?.dispose();
    _paths = recorder.endRecording();
    _pathsKey = key;
    _shadows = shadows;
    _bounds = bounds;
    // The image shows the shadows before, until the host lays these out:
    // a snapshot taken before it does, as a page's morph takes, draws the
    // paths.
    _readyPass = -1;
  }

  /// Lets go of the image, as the host no longer lays it out.
  void _forget() {
    _image.clear();
    _copy?.dispose();
    _copy = null;
    _copied = null;
    _readyPass = -1;
  }

  /// Lays the shadows where [toDevice] puts them, for this pass of the host.
  void align(Matrix4 toDevice) {
    final paths = _paths;
    if (paths == null ||
        !_image.update(
          _bounds,
          toDevice,
          paths,
          (canvas) => canvas.drawPicture(paths),
        )) {
      // The image left from before shows where the pane was.
      return;
    }
    final image = _image.image;
    if (_copy == null || !identical(_copied, image)) {
      final recorder = ui.PictureRecorder();
      _image.draw(Canvas(recorder));
      _copy?.dispose();
      _copy = recorder.endRecording();
      _copied = image;
    }
    _readyPass = _LiquidGlassHostLayer._pass;
  }

  /// What it draws: the image while the host keeps it on the device's
  /// pixels, the paths otherwise.
  ui.Picture? get picture =>
      _readyPass == _LiquidGlassHostLayer._pass ? _copy : _paths;

  /// The shadows as painted.
  ui.Picture? get paths => _paths;

  Rect get bounds => _bounds;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (picture case final picture?) {
      builder.addPicture(Offset.zero, picture);
    }
  }

  @override
  void dispose() {
    _paths?.dispose();
    _paths = null;
    _forget();
    super.dispose();
  }
}

extension on LiquidGlassPane {
  /// Casts [shadows] as [LiquidGlassPane._paintShadows] paints them, but
  /// without Impeller through a layer of their own.
  void _castShadows(
    PaintingContext context,
    Rect rect,
    BorderRadius corners,
    List<BoxShadow> shadows,
  ) {
    if (!_drawsFromImages) {
      _shadowLayer.layer = null;
      LiquidGlassPane._paintShadows(context.canvas, rect, corners, shadows);
      return;
    }
    final reach = shadows.fold(
      0.0,
      (reach, shadow) => math.max(
        reach,
        shadow.offset.distance + shadow.spreadRadius + shadow.blurRadius * 2,
      ),
    );
    final layer = (_shadowLayer.layer ??= _LiquidGlassShadowLayer())
      ..paint(
        rect,
        corners,
        shadows,
        rect.inflate(reach),
        LiquidGlassPane._paintShadows,
      );
    context.addLayer(layer);
  }
}

extension on _LiquidGlassLayer {
  /// The frost's rims as an image lying where [toDevice] puts the pane, once
  /// it is ready; null for their paths. The tint stays a path: an image of
  /// it would round its every pixel to the image's eight bits.
  ui.Image? _frostImage(Matrix4 toDevice) {
    // A menu's or an alert's shine adds its light to what lies under it,
    // which an image laid over would not.
    if (!_drawsFromImages || rim != null) {
      return null;
    }
    // A stroke reaches past an outline, where the frost's clip ends it.
    final bounds = (outline?.getBounds() ?? rect).inflate(style.rimWidth + 1);
    return _overlay.update(
          bounds,
          toDevice,
          (rect, corners, outline, style, rim),
          (canvas) => _drawFrost(canvas, overCapture: true, tinted: false),
        )
        ? _overlay.image
        : null;
  }
}

/// Where the host's coordinates lie on the device, from the layers above it.
Matrix4 _toDevice(Layer host) {
  final matrix = Matrix4.identity();
  for (var layer = host.parent; layer != null; layer = layer.parent) {
    if (_geometry(layer) case final geometry?) {
      matrix.setFrom(geometry.multiplied(matrix));
    }
  }
  return matrix;
}
