import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _side = GlassButtonGroup.thickness;

Widget _app(Widget child) => MaterialApp(
  // As main.dart's builder, so that the panes bend what is under them.
  builder: (context, child) => LiquidGlassScope(
    enabled: true,
    child: LiquidGlassHost(enabled: true, child: child!),
  ),
  home: Scaffold(
    backgroundColor: Colors.white,
    body: Center(child: child),
  ),
);

/// A button without a glyph, so that what shows of it is its platter.
IconButton _button(String tooltip, {VoidCallback? onPressed}) => IconButton(
  tooltip: tooltip,
  onPressed: onPressed ?? () {},
  icon: const SizedBox.square(dimension: 24),
);

Future<ByteData> _capture(WidgetTester tester, GlobalKey key) async {
  final pixels = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  return pixels!;
}

int _luma(ByteData pixels, int width, Offset at) {
  final i = (at.dy.toInt() * width + at.dx.toInt()) * 4;
  return pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2);
}

void main() {
  // The menus on glass, as main() installs them with the switch on.
  setUpAll(GlassSurfaces.install);

  testWidgets('without glass the buttons stand as they are, in a row', (
    tester,
  ) async {
    final children = [_button('撤销'), _button('选择')];
    await tester.pumpWidget(
      _app(GlassButtonGroup(glass: false, children: children)),
    );
    expect(find.byType(LiquidGlass), findsNothing);
    final row = tester.widget<Flex>(find.byType(Flex));
    expect(row.direction, Axis.horizontal);
    expect(row.children, same(children));
    // Material's own size, tap target and all.
    expect(tester.getSize(find.byType(IconButton).first), const Size(48, 48));
  });

  testWidgets('on glass they share one pane, a button 44 dp a side', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          children: [_button('撤销'), _button('选择'), _button('标签')],
        ),
      ),
    );
    expect(find.byType(LiquidGlass), findsOneWidget);
    final pane = tester.getRect(find.byType(LiquidGlass));
    expect(pane.size, const Size(3 * _side, _side));
    final buttons = find.byType(IconButton);
    for (var i = 0; i < 3; i++) {
      final rect = tester.getRect(buttons.at(i));
      expect(rect.size, const Size.square(_side));
      // Evenly, without a gap or a divider between them.
      expect(rect.left, pane.left + i * _side);
    }
  });

  testWidgets('a column along Axis.vertical', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          direction: Axis.vertical,
          children: [_button('上'), _button('下')],
        ),
      ),
    );
    final pane = tester.getRect(find.byType(LiquidGlass));
    expect(pane.size, const Size(_side, 2 * _side));
    expect(tester.getTopLeft(find.byTooltip('下')).dy, pane.top + _side);
  });

  testWidgets('a column is as wide as its widest button', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          direction: Axis.vertical,
          children: [
            _button('上'),
            TextButton(onPressed: () {}, child: const Text('全部收藏夹')),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final pane = tester.getRect(find.byType(LiquidGlass));
    final label = tester.getRect(find.byType(TextButton));
    expect(pane.width, label.width);
    expect(pane.width, greaterThan(_side));
    // The label on one line, the icon button centred above it.
    expect(tester.getSize(find.text('全部收藏夹')).height, lessThan(_side));
    expect(tester.getCenter(find.byTooltip('上')).dx, pane.center.dx);
    expect(tester.getSize(find.byTooltip('上')), const Size.square(_side));
  });

  testWidgets('a pressed button alone stands on a platter, inset 2 dp', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(300, 200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          key: key,
          child: GlassButtonGroup(
            glass: true,
            children: [_button('撤销'), _button('选择')],
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(key));
    final first = tester.getRect(find.byTooltip('撤销')).shift(-origin);
    final second = tester.getRect(find.byTooltip('选择')).shift(-origin);
    final before = await _capture(tester, key);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('撤销')),
    );
    // The press lands past the tap's deadline; its platter fades in after.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    final pressed = await _capture(tester, key);
    final width = (2 * _side).toInt();
    // Under the pressed button, and only there, the platter darkens it.
    expect(
      _luma(pressed, width, first.center),
      lessThan(_luma(before, width, first.center) - 30),
    );
    expect(
      _luma(pressed, width, second.center),
      _luma(before, width, second.center),
    );
    // No ripple: the same shade from the finger to the platter's edge.
    expect(
      _luma(pressed, width, first.center + const Offset(-15, 0)),
      _luma(pressed, width, first.center),
    );
    // Its edge stands in from the pane's.
    final edge = Offset(first.center.dx, first.top + 1);
    expect(_luma(pressed, width, edge), _luma(before, width, edge));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('disabled buttons read grey', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          children: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.redo)),
            const IconButton(onPressed: null, icon: Icon(Icons.label)),
          ],
        ),
      ),
    );
    Color colorOf(IconData icon) => tester
        .widget<RichText>(
          find.descendant(
            of: find.byIcon(icon),
            matching: find.byType(RichText),
          ),
        )
        .text
        .style!
        .color!;
    expect(colorOf(Icons.redo).a, 1);
    expect(colorOf(Icons.label).a, closeTo(0.38, 0.01));
  });

  testWidgets('each keeps its tooltip, semantics and keyboard focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var pressed = '';
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          children: [
            _button('撤销', onPressed: () => pressed = '撤销'),
            _button('选择', onPressed: () => pressed = '选择'),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byTooltip('撤销')),
      isSemantics(tooltip: '撤销', isButton: true, hasTapAction: true),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.byTooltip('选择'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressed, '选择');
    // A ring stands for the focus, in the primary color.
    final style = IconButtonTheme.of(focused).style!;
    expect(
      style.side!.resolve({WidgetState.focused}),
      BorderSide(color: Theme.of(focused).colorScheme.primary, width: 2),
    );
    semantics.dispose();
  });

  testWidgets('a menu grows out of its button and picks there', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          children: [
            _button('撤销'),
            // iOS's 「+ ⌄」.
            PopupMenuButton<String>(
              tooltip: '新建',
              icon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.add), Icon(Icons.expand_more, size: 16)],
              ),
              onSelected: (value) => picked = value,
              itemBuilder: (_) => const [
                PopupMenuItem(value: '文件夹', child: Text('文件夹')),
                PopupMenuItem(value: '标签', child: Text('标签')),
              ],
            ),
          ],
        ),
      ),
    );
    final button = tester.getRect(find.byTooltip('新建'));
    expect(button.height, _side);
    expect(
      tester.getRect(find.byType(LiquidGlass)).right,
      button.right,
    );
    expect(
      find.descendant(
        of: find.byType(GlassButtonGroup),
        matching: find.byType(GlassMenuSource),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    expect(find.text('文件夹'), findsOneWidget);
    expect(
      tester.widget<GlassMenuMorph>(find.byType(GlassMenuMorph)).anchor,
      button,
    );

    await tester.tap(find.text('标签'));
    await tester.pumpAndSettle();
    expect(picked, '标签');
    expect(find.text('文件夹'), findsNothing);
  });

  testWidgets('while all its buttons hide, the pane is not drawn', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          children: [
            // As a page's Obx that hides its button on another tab.
            Builder(builder: (_) => const SizedBox.shrink()),
            Builder(builder: (_) => const SizedBox.shrink()),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(LiquidGlass)), const Size(0, _side));
  });

  testWidgets('a lone button is the whole group, which can hide', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        GlassButtonGroup(
          glass: true,
          children: [_button('搜索', onPressed: () => taps++)],
        ),
      ),
    );
    final group = GlassButtonGroup.maybeOf(
      tester.element(find.byTooltip('搜索')),
    )!;
    expect(group.alone, isTrue);
    expect(group.box!.size, const Size.square(_side));

    final button = tester.element(find.byType(IconButton));
    group.hidden = true;
    await tester.pump();
    // Hidden, not built again: what it holds stays.
    expect(tester.element(find.byType(IconButton)), same(button));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byType(LiquidGlass),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0,
    );
    await tester.tap(find.byTooltip('搜索'), warnIfMissed: false);
    expect(taps, 0);

    group.hidden = false;
    await tester.pump();
    await tester.tap(find.byTooltip('搜索'));
    expect(taps, 1);
  });
}
