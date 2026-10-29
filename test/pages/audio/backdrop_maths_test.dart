import 'dart:math' as math;
import 'dart:typed_data';

import 'package:PiliPlus/pages/audio/backdrop/backdrop_maths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Twice the signed area of each triangle of [positions], y down: positive
/// while it keeps the grid's turn.
Iterable<double> _areas(Float32List positions) sync* {
  final indices = BackdropMesh.indices;
  for (var k = 0; k < indices.length; k += 3) {
    final a = indices[k] * 2, b = indices[k + 1] * 2, c = indices[k + 2] * 2;
    yield (positions[b] - positions[a]) *
            (positions[c + 1] - positions[a + 1]) -
        (positions[c] - positions[a]) * (positions[b + 1] - positions[a + 1]);
  }
}

Float32List _at(BackdropMesh mesh, double weight) {
  final out = Float32List(BackdropMesh.size * BackdropMesh.size * 2);
  mesh.lerp(weight, 1, 1, out);
  return out;
}

void main() {
  group('BackdropMesh', () {
    final meshes = [
      for (var seed = 0; seed < 200; seed++)
        BackdropMesh.generate(math.Random(seed)),
    ];

    test('stays inside the view, its border on the edges', () {
      const n = BackdropMesh.size;
      for (final mesh in meshes) {
        for (final state in [mesh.from, mesh.to]) {
          for (final v in state) {
            expect(v, inInclusiveRange(0, 1));
          }
          for (var i = 0; i < n; i++) {
            expect(state[i * 2 + 1], 0, reason: 'top');
            expect(state[((n - 1) * n + i) * 2 + 1], 1, reason: 'bottom');
            expect(state[(i * n) * 2], 0, reason: 'left');
            expect(state[(i * n + n - 1) * 2], 1, reason: 'right');
          }
        }
      }
    });

    test('never folds over, in either state or between them', () {
      for (final mesh in meshes) {
        for (final weight in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          for (final area in _areas(_at(mesh, weight))) {
            expect(area, greaterThan(0));
          }
        }
      }
    });

    test('its control points: the inner ones up to 0.6 cell off the grid', () {
      const n = BackdropMesh.controls;
      const cell = 1 / (n - 1);
      for (final mesh in meshes) {
        for (var k = 0; k < n * n; k++) {
          final (i, j) = (k % n, k ~/ n);
          final (x, y) = mesh.controlsFrom[k];
          final off = math.sqrt(
            math.pow(x - i * cell, 2) + math.pow(y - j * cell, 2),
          );
          final inner = i > 0 && i < n - 1 && j > 0 && j < n - 1;
          expect(off, lessThanOrEqualTo(inner ? 0.6 * cell + 1e-9 : 0));
        }
      }
    });

    test('2 to 8 inner points move, by up to half a cell', () {
      const cell = 1 / (BackdropMesh.controls - 1);
      for (final mesh in meshes) {
        var moved = 0;
        for (var k = 0; k < mesh.controlsFrom.length; k++) {
          final (x0, y0) = mesh.controlsFrom[k];
          final (x1, y1) = mesh.controlsTo[k];
          final move = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
          if (move > 0) moved++;
          expect(move, lessThanOrEqualTo(0.5 * cell + 1e-9));
        }
        expect(moved, inInclusiveRange(2, 8));
      }
    });

    test('draws each cell as two triangles', () {
      const cells = (BackdropMesh.size - 1) * (BackdropMesh.size - 1);
      expect(BackdropMesh.indices, hasLength(cells * 6));
      expect(
        BackdropMesh.indices.reduce(math.max),
        BackdropMesh.size * BackdropMesh.size - 1,
      );
    });

    test('zooms the image by 1.25', () {
      final uv = BackdropMesh.textureCoordinates(100, 100);
      expect(uv.first, closeTo(10, 1e-4));
      expect(uv.last, closeTo(90, 1e-4));
    });
  });

  group('BackdropMaths.morph', () {
    test('goes there and back every 3.5 seconds', () {
      for (var t = 0.0; t < 10; t += 0.37) {
        expect(
          BackdropMaths.morph(t + 3.5),
          closeTo(BackdropMaths.morph(t), 1e-9),
        );
      }
    });

    test('rests at either state 1.75 seconds apart', () {
      expect(BackdropMaths.morph(0.875), closeTo(0, 1e-9));
      expect(BackdropMaths.morph(2.625), closeTo(1, 1e-9));
      for (var t = 0.0; t < 3.5; t += 0.05) {
        expect(BackdropMaths.morph(t), inInclusiveRange(0, 1));
      }
    });
  });

  test('the copies orbit in 60, 45 and 35 seconds', () {
    expect(BackdropMaths.orbit(0, 60), closeTo(2 * math.pi, 1e-9));
    expect(BackdropMaths.orbit(1, 45), closeTo(2 * math.pi, 1e-9));
    expect(BackdropMaths.orbit(2, 35), closeTo(2 * math.pi, 1e-9));
  });

  test('the blur is 0.0454 of the diagonal, 119 pixels at 1080×2400', () {
    expect(BackdropMaths.blurSigma(1080, 2400), 119);
    expect(BackdropMaths.blurSigma(135, 300), 14);
  });

  group('colour', () {
    (double, double, double) apply(List<double> m, (double, double, double) c) {
      final (r, g, b) = c;
      return (
        m[0] * r + m[1] * g + m[2] * b,
        m[5] * r + m[6] * g + m[7] * b,
        m[10] * r + m[11] * g + m[12] * b,
      );
    }

    test('saturation keeps grey and pushes red away from it', () {
      final m = BackdropMaths.saturationMatrix(1.3);
      final (gr, gg, gb) = apply(m, (0.4, 0.4, 0.4));
      expect([gr, gg, gb], everyElement(closeTo(0.4, 1e-9)));
      final (r, g, b) = apply(m, (1, 0, 0));
      // luma 0.3, plus 1.3 times the distance from it
      expect(r, closeTo(1.21, 1e-9));
      expect(g, closeTo(-0.09, 1e-9));
      expect(b, closeTo(-0.09, 1e-9));
    });

    test('the last pass darkens a quarter, less 0.02, within 0.07 and 0.97', () {
      final (wr, wg, wb) = BackdropMaths.finish(1, 1, 1);
      expect([
        wr,
        wg,
        wb,
      ], everyElement(closeTo(0.9951171875 * 0.75 - 0.02, 1e-9)));
      final (br, bg, bb) = BackdropMaths.finish(0, 0, 0);
      expect([br, bg, bb], everyElement(0.07));
      final (gr, gg, gb) = BackdropMaths.finish(0.5, 0.5, 0.5);
      expect([gr, gg, gb], everyElement(closeTo(0.355, 1e-9)));
      // Red saturates past white, capped, and its other channels to the floor.
      final (r, g, b) = BackdropMaths.finish(1, 0, 0);
      expect(r, closeTo(0.9951171875 * 0.75 - 0.02, 1e-9));
      expect(g, 0.07);
      expect(b, 0.07);
    });

    test('white text always reads: nothing comes out above 0.73', () {
      final random = math.Random(1);
      for (var i = 0; i < 1000; i++) {
        final (r, g, b) = BackdropMaths.finish(
          random.nextDouble(),
          random.nextDouble(),
          random.nextDouble(),
        );
        for (final c in [r, g, b]) {
          expect(c, inInclusiveRange(0.07, 0.73));
        }
      }
    });

    test('sRGB to linear light', () {
      expect(BackdropMaths.toLinear(0), 0);
      expect(BackdropMaths.toLinear(1), closeTo(1, 1e-9));
      expect(BackdropMaths.toLinear(0.5), closeTo(0.214, 1e-3));
      expect(BackdropMaths.linearBytes[255], 255);
      expect(BackdropMaths.linearBytes[128], 55);
    });
  });
}
