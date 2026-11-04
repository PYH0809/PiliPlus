// After FlClash's tests of the host (https://github.com/chen08209/prism_ui,
// test/widgets/liquid_glass_host_test.dart, GPL-3.0), for what the port took
// from prism_ui 63450c0ac.
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);
const _clear = LiquidGlassStyle(tint: Colors.transparent, blur: 0);

Widget _app(
  Widget child, {
  bool enabled = true,
  LiquidGlassQuality quality = LiquidGlassQuality.ultra,
}) => MaterialApp(
  home: LiquidGlassScope(
    enabled: true,
    quality: quality,
    child: LiquidGlassHost(enabled: enabled, child: child),
  ),
);

Widget _pane(Rect rect, {LiquidGlassStyle style = _clear, Widget? child}) =>
    Positioned.fromRect(
      rect: rect,
      child: LiquidGlass(style: style, child: child),
    );

LiquidGlassCapture _capture() => LiquidGlassHost.debugLastCapture!;

class _HeldPane extends LeafRenderObjectWidget {
  const _HeldPane(
    this.rect,
    this.hold, {
    this.style = _clear,
    this.steadyFrost = false,
  });

  final Rect rect;
  final Rect hold;
  final LiquidGlassStyle style;
  final bool steadyFrost;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeldPane(rect, hold, style, steadyFrost);

  @override
  void updateRenderObject(BuildContext context, _RenderHeldPane renderObject) {
    renderObject
      ..rect = rect
      ..hold = hold
      ..style = style
      ..steadyFrost = steadyFrost
      ..markNeedsPaint();
  }
}

class _RenderHeldPane extends RenderBox {
  _RenderHeldPane(this.rect, this.hold, this.style, this.steadyFrost);

  Rect rect;
  Rect hold;
  LiquidGlassStyle style;
  bool steadyFrost;
  late final _pane = LiquidGlassPane(markNeedsPaint);

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _pane.paint(
      context,
      rect.shift(offset),
      shape: LiquidGlassCorners.circular(0),
      style: style,
      hold: hold.shift(offset),
      steadyFrost: steadyFrost,
    );
  }
}

Future<Color> _behind(WidgetTester tester, _Pane pane, Offset point) async {
  final texel = pane.place.topLeft + (point - pane.slot.topLeft) * pane.scale;
  final bytes = (await tester.runAsync(pane.atlas.toByteData))!;
  final offset = (texel.dy.floor() * pane.atlas.width + texel.dx.floor()) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

typedef _Pane = ({
  Rect pane,
  Rect slot,
  Rect place,
  double scale,
  int level,
  ui.Image atlas,
});

void main() {
  setUp(() => LiquidGlassHost.debugLastCapture = null);

  testWidgets('a host within another leaves its panes to the outer one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LiquidGlassHost(
          enabled: true,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: _red)),
              _pane(const Rect.fromLTWH(100, 100, 200, 100)),
            ],
          ),
        ),
      ),
    );

    final before = LiquidGlassHost.debugCaptures;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(LiquidGlassHost.debugCaptures - before, 1);
    expect(_capture().panes, hasLength(1));
  });

  testWidgets('a steady pane shrinking within its hold keeps one capture', (
    tester,
  ) async {
    const rect = Rect.fromLTWH(100, 100, 200, 100);
    const frost = LiquidGlassStyle(tint: Colors.transparent, blur: 12);
    Widget scene(double scale) => _app(
      Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(child: ColoredBox(color: _red)),
          ),
          Positioned.fill(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              origin: rect.center,
              child: const _HeldPane(
                rect,
                rect,
                style: frost,
                steadyFrost: true,
              ),
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(scene(1.2));
    expect(_capture().snapshots, 1);
    final first = _capture().panes.single;

    for (final scale in [1.1, 1.0]) {
      await tester.pumpWidget(scene(scale));
      expect(_capture().snapshots, 0);
      expect(_capture().panes.single.atlas, same(first.atlas));
    }
  });

  testWidgets('a steady hazed pane shrinking within its hold keeps one '
      'capture', (tester) async {
    const rect = Rect.fromLTWH(100, 100, 200, 100);
    const haze = LiquidGlassStyle(
      tint: Colors.transparent,
      blur: 0,
      haze: 0.72,
      hazeBlur: 15.6,
    );
    Widget scene(double scale) => _app(
      Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(child: ColoredBox(color: _red)),
          ),
          Positioned.fill(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              origin: rect.center,
              child: const _HeldPane(
                rect,
                rect,
                style: haze,
                steadyFrost: true,
              ),
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(scene(1.2));
    expect(_capture().snapshots, 1);

    for (final scale in [1.1, 1.0]) {
      await tester.pumpWidget(scene(scale));
      expect(_capture().snapshots, 0);
    }
  });

  testWidgets('panes in one group share a level and read past each other', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LiquidGlassGroup(
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: _red)),
              _pane(
                const Rect.fromLTWH(100, 100, 200, 100),
                style: const LiquidGlassStyle(tint: _blue, blur: 0),
              ),
              _pane(const Rect.fromLTWH(250, 150, 100, 100)),
            ],
          ),
        ),
      ),
    );

    final capture = _capture();
    final [lower, upper] = capture.panes;
    expect([lower.level, upper.level], [0, 0]);
    expect(upper.atlas, same(lower.atlas));
    expect(capture.snapshots, 1);
    expect(await _behind(tester, upper, const Offset(275, 175)), _red);
  });

  testWidgets('groups given one shared object are one level apart in the '
      'tree', (tester) async {
    final shared = Object();
    await tester.pumpWidget(
      _app(
        Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _red)),
            LiquidGlassGroup(
              shared: shared,
              child: Stack(
                children: [
                  _pane(
                    const Rect.fromLTWH(100, 100, 200, 100),
                    style: const LiquidGlassStyle(tint: _blue, blur: 0),
                  ),
                ],
              ),
            ),
            LiquidGlassGroup(
              shared: shared,
              child: Stack(
                children: [_pane(const Rect.fromLTWH(250, 150, 100, 100))],
              ),
            ),
          ],
        ),
      ),
    );

    final capture = _capture();
    final [lower, upper] = capture.panes;
    expect([lower.level, upper.level], [0, 0]);
    expect(upper.atlas, same(lower.atlas));
    expect(capture.snapshots, 1);
    expect(await _behind(tester, upper, const Offset(275, 175)), _red);
  });
}
