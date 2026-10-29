import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/pages/common/dyn/action_bar.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 412.0;
const _height = 800.0;
const _bottom = 24.0;

/// The bottom of a dynamic's page as the pages build it: the reply button
/// over the bar, sliding away together.
class _Bottom extends StatefulWidget {
  const _Bottom({required this.glass, this.maxWidth});

  final bool glass;
  final double? maxWidth;

  @override
  State<_Bottom> createState() => _BottomState();
}

class _BottomState extends State<_Bottom>
    with SingleTickerProviderStateMixin, BaseFabMixin, FabMixin {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            children: [
              const SizedBox(height: 700),
              // The end of the replies, as common_dyn_page builds it.
              Container(
                alignment: Alignment.center,
                margin: EdgeInsets.only(
                  bottom: _bottom + (widget.glass ? 16 : 0),
                ),
                height: 125,
                child: const Text('没有更多了'),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: SlideTransition(
            position: fabAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 14, bottom: 12),
                  child: GlassReplyButton(onTap: () {}),
                ),
                DynActionBar(
                  glass: widget.glass,
                  bottom: _bottom,
                  maxWidth: widget.maxWidth,
                  child: const Row(
                    children: [
                      Expanded(child: SizedBox(key: ValueKey('row'))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(_width, _height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

Rect _capsule(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(DynActionBar),
    matching: find.byType(LiquidGlass),
  ),
);

void main() {
  testWidgets('on glass, a capsule floats 14 in and 12 above the padding', (
    tester,
  ) async {
    await _pump(tester, const _Bottom(glass: true));
    final capsule = _capsule(tester);
    expect(capsule.left, 14);
    expect(capsule.right, _width - 14);
    expect(capsule.bottom, _height - _bottom - 12);
    expect(capsule.height, DynActionBar.height);
  });

  testWidgets('the reply button sits 14 from its end and 12 above it', (
    tester,
  ) async {
    await _pump(tester, const _Bottom(glass: true));
    final capsule = _capsule(tester);
    final reply = tester.getRect(find.byType(GlassReplyButton));
    expect(reply.size, const Size.square(56));
    expect(reply.right, capsule.right);
    expect(reply.bottom, capsule.top - 12);
  });

  testWidgets(
    "the reply button is of the bar's glass, thicker, its icon the theme's",
    (tester) async {
      await _pump(tester, const _Bottom(glass: true));
      Color tintOf(Type type) => tester
          .widget<LiquidGlass>(
            find.descendant(
              of: find.byType(type),
              matching: find.byType(LiquidGlass),
            ),
          )
          .style
          .tint;
      final reply = tintOf(GlassReplyButton);
      final bar = tintOf(DynActionBar);
      expect(reply.withValues(alpha: 1), bar.withValues(alpha: 1));
      expect(reply.a, greaterThan(bar.a));
      final button = find.byType(GlassReplyButton);
      final icon = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byIcon(Icons.reply)),
      );
      expect(
        icon.color,
        Theme.of(tester.element(button)).colorScheme.primary,
      );
    },
  );

  testWidgets('in landscape, the capsule keeps to the end, narrower', (
    tester,
  ) async {
    await _pump(tester, const _Bottom(glass: true, maxWidth: 300));
    final capsule = _capsule(tester);
    expect(capsule.width, 300);
    expect(capsule.right, _width - 14);
  });

  testWidgets('it slides away whole on hideFab and back on showFab', (
    tester,
  ) async {
    await _pump(tester, const _Bottom(glass: true));
    final state = tester.state<_BottomState>(find.byType(_Bottom));
    final rest = _capsule(tester);
    state.hideFab();
    await tester.pumpAndSettle();
    expect(_capsule(tester).top, greaterThanOrEqualTo(_height));
    state.showFab();
    await tester.pumpAndSettle();
    expect(_capsule(tester), rest);
  });

  testWidgets('没有更多了 stays above the capsule at the end', (tester) async {
    await _pump(tester, const _Bottom(glass: true));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('没有更多了')).bottom,
      lessThanOrEqualTo(_capsule(tester).top),
    );
  });

  testWidgets('without glass, the bar lies on the surface as before', (
    tester,
  ) async {
    await _pump(tester, const _Bottom(glass: false));
    final bar = find.byType(DynActionBar);
    expect(
      find.descendant(of: bar, matching: find.byType(LiquidGlass)),
      findsNothing,
    );
    final rect = tester.getRect(bar);
    expect(rect.left, 0);
    expect(rect.right, _width);
    expect(rect.bottom, _height);
    final container = tester.widget<Container>(
      find.descendant(of: bar, matching: find.byType(Container)).first,
    );
    expect(container.padding, const EdgeInsets.only(bottom: _bottom));
  });

  testWidgets('the reply button is labelled 评论 and answers Enter', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, Center(child: GlassReplyButton(onTap: () => taps++)));
    expect(find.byTooltip('评论'), findsOneWidget);
    expect(find.bySemanticsLabel('评论'), findsOneWidget);
    Focus.of(tester.element(find.byType(LiquidGlass))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  test('buttons on glass: no ripple, a platter only under a press', () {
    const colorScheme = ColorScheme.light();
    final style = glassActionButtonStyle(colorScheme);
    expect(style.splashFactory, NoSplash.splashFactory);
    expect(style.overlayColor!.resolve({}), Colors.transparent);
    expect(
      style.overlayColor!.resolve({WidgetState.pressed}),
      glassPlatterColor(colorScheme),
    );
    expect(
      style.foregroundColor!.resolve({}),
      colorScheme.onSurfaceVariant,
    );
  });
}
