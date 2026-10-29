import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The numbers of Apple Music's Now Playing background, as
/// [MusicFlow](https://github.com/frs0n/MusicFlow) recovered them from
/// macOS Music 1.7.2's shaders. Only the numbers: its code and meshes are
/// not reused.
abstract final class BackdropMaths {
  /// The three copies of the cover orbit the centre in these periods, in
  /// seconds, and spin twice as fast.
  static const orbitPeriods = [60.0, 45.0, 35.0];

  /// Where each copy sits off the centre, in the view's normalised
  /// coordinates (-1 to 1 across, y up).
  static const offsets = [(0.0, 0.0), (-0.5, 0.7), (-0.95, -0.7)];

  /// The copies' saturation, before the blur.
  static const coverSaturation = 1.3;

  /// The blur's sigma, a share of the target's diagonal.
  static const blurOfDiagonal = 0.04539470697716646;

  /// Each leg of the mesh's morph, there or back, takes this long.
  static const morphLeg = 1.75;

  /// The mesh zooms the blurred image this much.
  static const zoom = 1.25;

  /// Reduce Motion runs it all this much slower.
  static const reducedMotion = 10.0;

  /// A new cover fades in over this long.
  static const dissolve = Duration(milliseconds: 500);

  static const _luma = (0.30, 0.59, 0.11);

  /// The blur's sigma on a target of [width]×[height] pixels.
  static double blurSigma(double width, double height) =>
      (math.sqrt(width * width + height * height) * blurOfDiagonal)
          .floorToDouble();

  /// How far the mesh is morphed at [t] seconds: there and back again every
  /// 2 × [morphLeg], easing at each end.
  static double morph(double t) {
    final q = math.acos(math.sin(t * math.pi / morphLeg)) / math.pi;
    return q * q * (3 - 2 * q);
  }

  /// The angle copy [index] has turned through at [t] seconds.
  static double orbit(int index, double t) =>
      2 * math.pi * t / orbitPeriods[index];

  /// A saturation matrix for a `ColorFilter.matrix`, weighing the channels
  /// as the shaders do.
  static List<double> saturationMatrix(double saturation) {
    final (r, g, b) = _luma;
    final s = saturation;
    final m = 1 - s;
    return [
      m * r + s, m * g, m * b, 0, 0, //
      m * r, m * g + s, m * b, 0, 0,
      m * r, m * g, m * b + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  /// The last pass, as `shaders/audio_backdrop.frag` does it without its
  /// noise: saturation 2 capped below white, a quarter of the way to black
  /// less 0.02, then held within 0.07 and 0.97 so white text reads on it.
  static (double, double, double) finish(double r, double g, double b) {
    final (wr, wg, wb) = _luma;
    final luma = r * wr + g * wg + b * wb;
    double channel(double c) {
      final saturated = math.min(0.9951171875, luma + 2 * (c - luma));
      return (saturated * 0.75 - 0.02).clamp(0.07, 0.97);
    }

    return (channel(r), channel(g), channel(b));
  }

  /// Linear light of an sRGB encoded [value], both 0 to 1. Music samples the
  /// cover as sRGB and works on, and shows, its linear values as they are.
  static double toLinear(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  /// [toLinear] for each byte value.
  static final Uint8List linearBytes = Uint8List.fromList([
    for (var i = 0; i < 256; i++) (toLinear(i / 255) * 255).round(),
  ]);
}

/// The grid the blurred image is drawn through: [controls]×[controls]
/// points in two states, the mesh morphing between them, smoothed to
/// [size]×[size] vertices. Generated with the statistics of Music's own:
/// the inner points up to [maxOffset] of a cell off the regular grid, and
/// 2 to 8 of them moving by up to [maxMove] of a cell in the morph. The
/// border stays where it is, so the mesh always covers the view, and no
/// triangle of it folds over or pinches thin.
class BackdropMesh {
  BackdropMesh._(this.controlsFrom, this.controlsTo, this.from, this.to);

  static const controls = 6;
  static const size = 41;
  static const maxOffset = 0.6;
  static const maxMove = 0.5;

  /// The points on the regular grid, as a share of the cell, never come
  /// closer than this, so the mesh does not fold over.
  static const _minGap = 0.25;

  /// The control points of either state, row by row, 0 to 1 across.
  @visibleForTesting
  final List<(double, double)> controlsFrom;
  @visibleForTesting
  final List<(double, double)> controlsTo;

  /// The vertices of either state, x then y, 0 to 1 across the view.
  final Float32List from;
  final Float32List to;

  /// The least a triangle may be, of its size on the regular grid.
  static const minArea = 0.25;

  static const _cell = 1 / (controls - 1);

  factory BackdropMesh.generate(math.Random random) {
    while (true) {
      final initial = _jitter(random);
      final morphed = _move(random, initial);
      final mesh = BackdropMesh._(
        initial,
        morphed,
        _smooth(initial),
        _smooth(morphed),
      );
      if (mesh._isOpen) return mesh;
    }
  }

  /// Whether every triangle keeps its turn and some room all along the
  /// morph: the smoothing can overshoot where the points crowd.
  bool get _isOpen {
    const regular = 1 / ((size - 1) * (size - 1));
    final positions = Float32List(from.length);
    for (final weight in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      lerp(weight, 1, 1, positions);
      for (var k = 0; k < indices.length; k += 3) {
        final a = indices[k] * 2;
        final b = indices[k + 1] * 2;
        final c = indices[k + 2] * 2;
        final area =
            (positions[b] - positions[a]) *
                (positions[c + 1] - positions[a + 1]) -
            (positions[c] - positions[a]) *
                (positions[b + 1] - positions[a + 1]);
        if (area < minArea * regular) return false;
      }
    }
    return true;
  }

  /// Writes the vertices at [weight] into [out], in pixels of a view of
  /// [width]×[height].
  void lerp(double weight, double width, double height, Float32List out) {
    for (var i = 0; i < from.length; i += 2) {
      out[i] = (from[i] + (to[i] - from[i]) * weight) * width;
      out[i + 1] = (from[i + 1] + (to[i + 1] - from[i + 1]) * weight) * height;
    }
  }

  /// The regular grid's texture coordinates, zoomed by
  /// [BackdropMaths.zoom], in pixels of an image of [width]×[height].
  static Float32List textureCoordinates(double width, double height) {
    final out = Float32List(size * size * 2);
    const scale = 1 / BackdropMaths.zoom;
    for (var j = 0; j < size; j++) {
      for (var i = 0; i < size; i++) {
        final k = (j * size + i) * 2;
        out[k] = ((i / (size - 1) - 0.5) * scale + 0.5) * width;
        out[k + 1] = ((j / (size - 1) - 0.5) * scale + 0.5) * height;
      }
    }
    return out;
  }

  /// Two triangles to each cell of the grid.
  static final Uint16List indices = () {
    final out = Uint16List((size - 1) * (size - 1) * 6);
    var k = 0;
    for (var j = 0; j < size - 1; j++) {
      for (var i = 0; i < size - 1; i++) {
        final a = j * size + i;
        final b = a + 1;
        final c = a + size;
        final d = c + 1;
        out
          ..[k++] = a
          ..[k++] = b
          ..[k++] = c
          ..[k++] = b
          ..[k++] = d
          ..[k++] = c;
      }
    }
    return out;
  }();

  static bool _isInner(int i, int j) =>
      i > 0 && i < controls - 1 && j > 0 && j < controls - 1;

  static List<(double, double)> _grid() => [
    for (var j = 0; j < controls; j++)
      for (var i = 0; i < controls; i++) (i * _cell, j * _cell),
  ];

  static (double, double) _offset(math.Random random, double maxCells) {
    final angle = random.nextDouble() * 2 * math.pi;
    final length = maxCells * _cell * math.sqrt(random.nextDouble());
    return (math.cos(angle) * length, math.sin(angle) * length);
  }

  static List<(double, double)> _jitter(math.Random random) {
    while (true) {
      final points = _grid();
      for (var j = 1; j < controls - 1; j++) {
        for (var i = 1; i < controls - 1; i++) {
          final (x, y) = points[j * controls + i];
          final (dx, dy) = _offset(random, maxOffset);
          points[j * controls + i] = (x + dx, y + dy);
        }
      }
      if (_unfolded(points)) return points;
    }
  }

  static List<(double, double)> _move(
    math.Random random,
    List<(double, double)> initial,
  ) {
    final inner = [
      for (var k = 0; k < initial.length; k++)
        if (_isInner(k % controls, k ~/ controls)) k,
    ];
    while (true) {
      final points = [...initial];
      final count = 2 + random.nextInt(7);
      for (final k in (inner..shuffle(random)).take(count)) {
        final (x, y) = points[k];
        final (dx, dy) = _offset(random, maxMove);
        points[k] = (x + dx, y + dy);
      }
      if (_unfolded(points)) return points;
    }
  }

  /// Whether each row runs left to right and each column top to bottom with
  /// room between the points.
  static bool _unfolded(List<(double, double)> points) {
    const gap = _minGap * _cell;
    for (var j = 0; j < controls; j++) {
      for (var i = 0; i < controls; i++) {
        final (x, y) = points[j * controls + i];
        if (i > 0 && x - points[j * controls + i - 1].$1 < gap) return false;
        if (j > 0 && y - points[(j - 1) * controls + i].$2 < gap) return false;
      }
    }
    return true;
  }

  /// A Catmull-Rom surface through the control points, at [size]×[size],
  /// held within the view.
  static Float32List _smooth(List<(double, double)> points) {
    const steps = (size - 1) ~/ (controls - 1);
    (double, double) at(int i, int j) =>
        points[j.clamp(0, controls - 1) * controls + i.clamp(0, controls - 1)];

    double spline(double p0, double p1, double p2, double p3, double t) =>
        0.5 *
        (2 * p1 +
            (p2 - p0) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
            (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);

    // Along the rows first, then down the columns.
    final rows = List.generate(
      controls,
      (j) => List.generate(size, (v) {
        final i = math.min(v ~/ steps, controls - 2);
        final t = v / steps - i;
        final (x0, y0) = at(i - 1, j);
        final (x1, y1) = at(i, j);
        final (x2, y2) = at(i + 1, j);
        final (x3, y3) = at(i + 2, j);
        return (spline(x0, x1, x2, x3, t), spline(y0, y1, y2, y3, t));
      }),
    );
    final out = Float32List(size * size * 2);
    for (var v = 0; v < size; v++) {
      final j = math.min(v ~/ steps, controls - 2);
      final t = v / steps - j;
      for (var u = 0; u < size; u++) {
        (double, double) row(int r) => rows[r.clamp(0, controls - 1)][u];
        final (x0, y0) = row(j - 1);
        final (x1, y1) = row(j);
        final (x2, y2) = row(j + 1);
        final (x3, y3) = row(j + 2);
        final k = (v * size + u) * 2;
        out[k] = spline(x0, x1, x2, x3, t).clamp(0, 1);
        out[k + 1] = spline(y0, y1, y2, y3, t).clamp(0, 1);
      }
    }
    return out;
  }
}
