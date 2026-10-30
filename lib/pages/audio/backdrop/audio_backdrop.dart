import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliPlus/pages/audio/backdrop/backdrop_maths.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:material_ui/material_ui.dart';

/// Apple Music's Now Playing background made of [image]: three copies of it
/// orbit and spin, blurred, then warped through a slowly morphing mesh and
/// saturated and darkened so that white reads on it, in either theme.
///
/// It moves [fps] times a second while it shows, and holds still while a
/// page covers it or the app is away, going on from where it stopped. A
/// [Ticker] would draw a frame on every vsync, and every frame draws the
/// page and its glass again; this asks only for the frames it changes.
/// Without Impeller it never moves, see [moves].
class AudioBackdrop extends StatefulWidget {
  const AudioBackdrop({
    super.key,
    required this.image,
    required this.placeholder,
  });

  /// The cover, or null while there is none.
  final ImageProvider? image;

  /// Stands for the cover until it loads, or when it fails to.
  final Color placeholder;

  /// How often it moves. At 0 it draws once for each cover.
  ///
  /// As Apple's web player. On a OnePlus 7 Pro with Impeller, the glass over
  /// it kept 95% of frames under 7 ms at 15 a second; at 30, 7% of them took
  /// over 11.1 ms, a frame at 90 Hz.
  static const fps = 15;

  /// Whether it moves: only with Impeller's shader filters, as the glass
  /// checks for them. Without, it is drawn once for each cover, still fading
  /// one cover into the next. Skia's glass can't carry what it captured over
  /// to the next frame, so while the backdrop moves the glass over it draws
  /// and blurs it again every frame: on a OnePlus 7 Pro, 14 ms a frame at
  /// any rate, against 3 to 6 with the glass off.
  static bool get moves =>
      debugMovesOverride ?? ui.ImageFilter.isShaderFilterSupported;

  @visibleForTesting
  static bool? debugMovesOverride;

  /// [fps] while measuring what the glass over it costs at each rate.
  static final debugFps = ValueNotifier<int?>(null);

  /// How often it moves now: [debugFps], else [fps] where it [moves].
  static int get currentFps => debugFps.value ?? (moves ? fps : 0);

  /// The cover is read this small: it ends up blurred.
  static const coverSize = 64;

  /// The blurred, warped image is this fraction of the view's pixels.
  static const resolution = 1 / 8;

  static const _shaderAsset = 'shaders/audio_backdrop.frag';

  @override
  State<AudioBackdrop> createState() => AudioBackdropState();
}

@visibleForTesting
class AudioBackdropState extends State<AudioBackdrop> {
  final _mesh = BackdropMesh.generate(math.Random());
  final _repaint = _Repaint();

  ui.FragmentProgram? _program;

  /// The cover's linear light, at [AudioBackdrop.coverSize].
  ui.Image? _art;

  /// The cover fading out under [_art], and when [_art] came.
  ui.Image? _previous;
  Duration? _dissolveStart;

  /// [AudioBackdrop.placeholder] as a cover.
  ui.Image? _placeholder;

  /// The blurred, warped cover last drawn, and what for.
  _Frame? _frame;

  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: _onError);

  /// How long it has run, from the frames' time stamps, and the last frame
  /// it counted, null while it is stopped so that it goes on where it was.
  Duration _elapsed = .zero;
  Duration? _lastFrame;
  double _time = 0;
  Timer? _timer;
  int _timerFps = 0;

  ValueListenable<TickerModeData>? _tickerMode;
  late final AppLifecycleListener _lifecycle;
  bool _appShown = true;
  bool _reduceMotion = false;

  /// The backdrop's own time, in seconds: it runs while the backdrop moves,
  /// a tenth as fast with Reduce Motion on.
  @visibleForTesting
  double get time => _time;

  /// How far the latest cover has faded in, 0 to 1.
  @visibleForTesting
  double get dissolve {
    final start = _dissolveStart;
    if (start == null) return 1;
    return ((_elapsed - start).inMicroseconds /
            BackdropMaths.dissolve.inMicroseconds)
        .clamp(0.0, 1.0);
  }

  /// Whether it is moving now.
  @visibleForTesting
  bool get isRunning => _timer != null;

  /// Whether it shows a cover, not the placeholder.
  @visibleForTesting
  bool get hasCover => _art != null;

  /// Whether its last pass is drawn with the shader, loaded once.
  @visibleForTesting
  bool get hasShader => _program != null;

  /// The times it drew the blurred, warped cover.
  @visibleForTesting
  int renders = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    AudioBackdrop.debugFps.addListener(_schedule);
    // The engine keeps the program once loaded.
    ui.FragmentProgram.fromAsset(AudioBackdrop._shaderAsset).then(
      (program) {
        if (mounted) {
          _program = program;
          _repaint.ping();
        }
      },
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack, library: '听视频'),
        );
      },
    );
    _makePlaceholder();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerMode = TickerMode.getValuesNotifier(context);
    if (tickerMode != _tickerMode) {
      _tickerMode?.removeListener(_schedule);
      _tickerMode = tickerMode..addListener(_schedule);
    }
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _resolve();
    _schedule();
  }

  @override
  void didUpdateWidget(AudioBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolve();
    if (widget.placeholder != oldWidget.placeholder) _makePlaceholder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stream?.removeListener(_listener);
    _tickerMode?.removeListener(_schedule);
    AudioBackdrop.debugFps.removeListener(_schedule);
    _lifecycle.dispose();
    _repaint.dispose();
    _art?.dispose();
    _previous?.dispose();
    _placeholder?.dispose();
    _frame?.image.dispose();
    _frame?.shader?.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    _appShown = switch (state) {
      .resumed || .inactive => true,
      .hidden || .paused || .detached => false,
    };
    _schedule();
  }

  int get _fps => AudioBackdrop.currentFps;

  bool get _dissolving => _dissolveStart != null;

  /// Asks for frames while it shows and has something to move.
  void _schedule() {
    if (!mounted) return;
    final shown = (_tickerMode?.value.enabled ?? true) && _appShown;
    // At 0 a second it only moves to fade a new cover in.
    final fps = _fps > 0 ? _fps : (_dissolving ? AudioBackdrop.fps : 0);
    if (!shown || fps == 0) {
      _timer?.cancel();
      _timer = null;
      _lastFrame = null;
      return;
    }
    if (_timer == null || _timerFps != fps) {
      _timer?.cancel();
      _timerFps = fps;
      _timer = Timer.periodic(
        Duration(microseconds: Duration.microsecondsPerSecond ~/ fps),
        (_) => _repaint.ping(),
      );
    }
  }

  /// Counts the time since the last frame it drew, as it draws one.
  void _advance() {
    final frame = SchedulerBinding.instance.currentFrameTimeStamp;
    final last = _lastFrame;
    _lastFrame = _timer == null ? null : frame;
    if (last == null || frame <= last) return;
    final step = frame - last;
    _elapsed += step;
    // Still at 0 a second, as it only runs to fade a new cover in.
    if (_fps > 0) {
      final seconds = step.inMicroseconds / Duration.microsecondsPerSecond;
      _time += _reduceMotion ? seconds / BackdropMaths.reducedMotion : seconds;
    }
    if (_dissolving && dissolve >= 1) {
      _previous?.dispose();
      _previous = null;
      _dissolveStart = null;
      // After this frame, not in the middle of painting it.
      scheduleMicrotask(_schedule);
    }
  }

  void _resolve() {
    final provider = widget.image;
    final stream = provider == null
        ? null
        : ResizeImage(
            provider,
            width: AudioBackdrop.coverSize,
            height: AudioBackdrop.coverSize,
            policy: .fit,
          ).resolve(createLocalImageConfiguration(context));
    if (stream?.key == _stream?.key && stream != null) return;
    _stream?.removeListener(_listener);
    // Before listening: a cover in the cache comes back at once, from inside
    // addListener.
    _stream = stream;
    if (stream == null) {
      _setArt(null);
    } else {
      stream.addListener(_listener);
    }
  }

  Future<void> _onImage(ImageInfo info, bool synchronousCall) async {
    final stream = _stream;
    final linear = await _linearLight(info.image);
    info.dispose();
    if (!mounted || stream != _stream) {
      linear?.dispose();
      return;
    }
    _setArt(linear);
  }

  void _onError(Object error, StackTrace? stack) {
    // The placeholder stands in, as it does before a cover loads.
    _setArt(null);
  }

  /// Fades [art] in, or the placeholder for null.
  void _setArt(ui.Image? art) {
    if (art == null && _art == null) return;
    _previous?.dispose();
    _previous = _art;
    _art = art;
    _dissolveStart = _elapsed;
    _schedule();
    _repaint.ping();
  }

  Future<void> _makePlaceholder() async {
    final color = widget.placeholder;
    int channel(double value) =>
        BackdropMaths.linearBytes[(value * 255).round()];
    final pixels = Uint8List.fromList([
      channel(color.r),
      channel(color.g),
      channel(color.b),
      255,
    ]);
    final image = await _fromPixels(pixels, 1, 1);
    if (!mounted) {
      image.dispose();
      return;
    }
    _placeholder?.dispose();
    _placeholder = image;
    _repaint.ping();
  }

  /// [image] in linear light, as Music samples the cover as sRGB and keeps on
  /// with the linear values.
  static Future<ui.Image?> _linearLight(ui.Image image) async {
    final data = await image.toByteData(format: .rawStraightRgba);
    if (data == null) return null;
    final pixels = data.buffer.asUint8List();
    final table = BackdropMaths.linearBytes;
    for (var i = 0; i < pixels.length; i += 4) {
      pixels
        ..[i] = table[pixels[i]]
        ..[i + 1] = table[pixels[i + 1]]
        ..[i + 2] = table[pixels[i + 2]];
    }
    return _fromPixels(pixels, image.width, image.height);
  }

  static Future<ui.Image> _fromPixels(Uint8List pixels, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      .rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BackdropPainter(this, MediaQuery.devicePixelRatioOf(context)),
      ),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.state, this.pixelRatio)
    : super(repaint: state._repaint);

  final AudioBackdropState state;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    state._advance();
    final art = state._art ?? state._placeholder;
    if (art == null || size.isEmpty) return;
    final frame = _frame(art, size);
    final rect = Offset.zero & size;
    final program = state._program;
    if (program == null) {
      canvas.drawImageRect(
        frame.image,
        Offset.zero & Size(frame.width.toDouble(), frame.height.toDouble()),
        rect,
        Paint()..filterQuality = .low,
      );
      return;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ((frame.shader ??= program.fragmentShader())
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, pixelRatio)
          ..setImageSampler(0, frame.image, filterQuality: .low)),
    );
  }

  _Frame _frame(ui.Image art, Size size) {
    final width = math.max(
      1,
      (size.width * pixelRatio * AudioBackdrop.resolution).ceil(),
    );
    final height = math.max(
      1,
      (size.height * pixelRatio * AudioBackdrop.resolution).ceil(),
    );
    final previous = state._dissolveStart == null
        ? null
        : state._previous ?? state._placeholder;
    final dissolve = previous == null ? 1.0 : state.dissolve;
    final time = state.time;
    final cached = state._frame;
    if (cached != null &&
        cached.width == width &&
        cached.height == height &&
        cached.time == time &&
        cached.art == art &&
        cached.dissolve == dissolve) {
      return cached;
    }
    final image = _render(art, previous, dissolve, time, width, height);
    state.renders++;
    cached?.image.dispose();
    return state._frame = _Frame(
      image: image,
      width: width,
      height: height,
      time: time,
      art: art,
      dissolve: dissolve,
      shader: cached?.shader,
    );
  }

  static final _coverFilter = ColorFilter.matrix(
    BackdropMaths.saturationMatrix(BackdropMaths.coverSaturation),
  );

  /// Three copies of the cover, orbiting, blurred, then drawn through the
  /// mesh, at [width]×[height] pixels.
  ui.Image _render(
    ui.Image art,
    ui.Image? previous,
    double dissolve,
    double time,
    int width,
    int height,
  ) {
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final sigma = BackdropMaths.blurSigma(bounds.width, bounds.height);
    final black = Paint()..color = Colors.black;

    final orbits = ui.PictureRecorder();
    final canvas = Canvas(orbits, bounds)
      ..drawRect(bounds, black)
      // The edges blur into black.
      ..saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: .decal,
          ),
      )
      ..drawRect(bounds, black);
    final paint = Paint()
      ..colorFilter = _coverFilter
      ..filterQuality = .low;
    void drawCover(ui.Image image, double opacity) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTRB(-1, -1, 1, 1),
        paint..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }

    for (var i = 0; i < BackdropMaths.offsets.length; i++) {
      final angle = BackdropMaths.orbit(i, time);
      final (dx, dy) = BackdropMaths.offsets[i];
      // Music turns, moves and turns each copy in the view's normalised
      // coordinates, y up; here y runs down, which turns the other way.
      canvas
        ..save()
        ..translate(bounds.width / 2, bounds.height / 2)
        ..scale(bounds.width / 2, bounds.height / 2)
        ..rotate(-angle)
        ..translate(dx, -dy)
        ..rotate(-angle);
      if (previous != null && dissolve < 1) drawCover(previous, 1);
      drawCover(art, dissolve);
      canvas.restore();
    }
    canvas.restore();
    final blurred = orbits.endRecording().toImageSync(width, height);

    final positions = Float32List(BackdropMesh.size * BackdropMesh.size * 2);
    state._mesh.lerp(
      BackdropMaths.morph(time),
      bounds.width,
      bounds.height,
      positions,
    );
    final vertices = ui.Vertices.raw(
      .triangles,
      positions,
      textureCoordinates: BackdropMesh.textureCoordinates(
        bounds.width,
        bounds.height,
      ),
      indices: BackdropMesh.indices,
    );
    final warp = ui.PictureRecorder();
    Canvas(warp, bounds).drawVertices(
      vertices,
      .srcOver,
      Paint()
        ..shader = ImageShader(
          blurred,
          .clamp,
          .clamp,
          Matrix4.identity().storage,
          filterQuality: .low,
        ),
    );
    final image = warp.endRecording().toImageSync(width, height);
    vertices.dispose();
    blurred.dispose();
    return image;
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.pixelRatio != pixelRatio;
}

class _Frame {
  _Frame({
    required this.image,
    required this.width,
    required this.height,
    required this.time,
    required this.art,
    required this.dissolve,
    this.shader,
  });

  final ui.Image image;
  final int width;
  final int height;
  final double time;
  final ui.Image art;
  final double dissolve;
  ui.FragmentShader? shader;
}
