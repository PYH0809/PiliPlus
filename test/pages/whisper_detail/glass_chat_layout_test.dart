import 'package:PiliPlus/common/widgets/flutter/chat_list_view.dart';
import 'package:PiliPlus/pages/dynamics/widgets/glass_header.dart';
import 'package:PiliPlus/pages/whisper_detail/widget/glass_chat_layout.dart';
import 'package:PiliPlus/pages/whisper_detail/widget/glass_input_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 412.0;
const _height = 800.0;

// The input bar's height, its gap under it included.
const _barHeight = GlassInputBar.height + GlassInputBar.gap;

/// A chat as the whisper page lays it out on glass: [count] messages 60 tall
/// under the input bar and, [panelHeight] tall, the emotes under it.
class _Chat extends StatelessWidget {
  const _Chat({
    required this.inset,
    this.panelHeight = 0,
    this.count = 30,
    this.controller,
    this.onMessagesTouched,
  });

  final ChatBarInset inset;
  final double panelHeight;
  final int count;
  final ScrollController? controller;
  final VoidCallback? onMessagesTouched;

  @override
  Widget build(BuildContext context) {
    return GlassChatLayout(
      inset: inset,
      messages: Listener(
        onPointerDown: (_) => onMessagesTouched?.call(),
        behavior: .opaque,
        child: InsetChatListView.separated(
          inset: inset,
          maxExtent: 625,
          controller: controller,
          itemCount: count,
          padding: const .all(kChatListPadding),
          itemBuilder: (context, index) =>
              SizedBox(key: ValueKey(index), height: 60),
          separatorBuilder: (context, index) => const SizedBox(height: 12),
        ),
      ),
      bar: Column(
        key: const ValueKey('bar'),
        mainAxisSize: .min,
        children: [
          GlassInputBar(
            leading: GlassCircle(
              icon: Icons.emoji_emotions_outlined,
              tooltip: '表情',
              onTap: () {},
            ),
            field: const SizedBox(height: GlassInputBar.height),
            trailing: GlassInputButton(
              icon: Icons.add_photo_alternate_outlined,
              tooltip: '图片',
              onPressed: () {},
            ),
          ),
          // The emotes, opaque, in the keyboard's place.
          SizedBox(
            width: double.infinity,
            height: panelHeight,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: .vertical(top: .circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(_width, _height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Material(child: child)),
  );
}

void main() {
  testWidgets('the newest message clears the bar in the frame it moves', (
    tester,
  ) async {
    final inset = ChatBarInset();
    addTearDown(inset.dispose);
    for (final panelHeight in [0.0, 344.0, 174.0, 0.0]) {
      // One frame, as when the keyboard moves the bar.
      await _pump(tester, _Chat(inset: inset, panelHeight: panelHeight));
      expect(inset.value, _barHeight + panelHeight);
      final barTop = tester.getTopLeft(find.byKey(const ValueKey('bar'))).dy;
      expect(barTop, _height - _barHeight - panelHeight);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey(0))).dy,
        barTop - kChatListPadding,
      );
    }
  });

  testWidgets('older messages scroll on under the bar', (tester) async {
    final inset = ChatBarInset();
    final controller = ScrollController();
    addTearDown(inset.dispose);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      _Chat(inset: inset, controller: controller),
    );
    controller.jumpTo(200);
    await tester.pump();
    // The list spans the page, so a message scrolled down past the bar's top
    // is still laid out there, for the glass to show through it.
    expect(tester.getSize(find.byType(Scrollable)).height, _height);
    final message = tester.getRect(find.byKey(const ValueKey(2)));
    expect(message.bottom, greaterThan(_height - _barHeight));
    expect(message.top, lessThan(_height));
  });

  testWidgets('a short chat still starts at the top', (tester) async {
    final inset = ChatBarInset();
    addTearDown(inset.dispose);
    await _pump(tester, _Chat(inset: inset, count: 2));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(1))).dy,
      kChatListPadding,
    );
  });

  testWidgets('the panes and the panel take touches, the rest go through', (
    tester,
  ) async {
    final inset = ChatBarInset();
    addTearDown(inset.dispose);
    const panelHeight = 200.0;
    var touched = 0;
    await _pump(
      tester,
      _Chat(
        inset: inset,
        panelHeight: panelHeight,
        onMessagesTouched: () => touched++,
      ),
    );
    const panesY =
        _height - panelHeight - _barHeight + GlassInputBar.height / 2;
    Future<bool> reachesMessages(Offset position) async {
      final before = touched;
      await tester.tapAt(position);
      return touched > before;
    }

    // The circle, the capsule round its button, and the emotes.
    const circle = Offset(GlassInputBar.margin + 20, panesY);
    expect(await reachesMessages(circle), isFalse);
    final button = tester.getRect(find.byTooltip('图片'));
    expect(await reachesMessages(button.center), isFalse);
    expect(await reachesMessages(button.topLeft + const Offset(1, 1)), isFalse);
    expect(await reachesMessages(const Offset(_width / 2, panesY)), isFalse);
    expect(
      await reachesMessages(
        const Offset(_width / 2, _height - panelHeight / 2),
      ),
      isFalse,
    );

    // Beside the panes, between them and in the gap under them, the
    // messages under the bar take touches and drags.
    const between = GlassInputBar.margin + GlassInputBar.height + 4;
    for (final position in [
      const Offset(GlassInputBar.margin / 2, panesY),
      const Offset(between, panesY),
      const Offset(_width / 2, _height - panelHeight - GlassInputBar.gap / 2),
      const Offset(_width / 2, _height / 3),
    ]) {
      expect(await reachesMessages(position), isTrue, reason: '$position');
    }
  });

  testWidgets('the capsule grows with the text, bottoms level', (
    tester,
  ) async {
    Future<void> pumpBar(double fieldHeight) => _pump(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: GlassInputBar(
          leading: const SizedBox.square(
            key: ValueKey('leading'),
            dimension: GlassInputBar.height,
          ),
          field: SizedBox(key: const ValueKey('field'), height: fieldHeight),
          trailing: GlassInputButton(
            icon: Icons.arrow_upward,
            tooltip: '发送',
            filled: true,
            onPressed: () {},
          ),
        ),
      ),
    );

    await pumpBar(20);
    final bar = find.byType(GlassInputBar);
    expect(
      tester.getSize(bar).height,
      GlassInputBar.height + GlassInputBar.gap,
    );

    await pumpBar(100);
    expect(tester.getSize(bar).height, 100 + GlassInputBar.gap);
    final leading = tester.getRect(find.byKey(const ValueKey('leading')));
    final button = tester.getRect(find.byTooltip('发送'));
    expect(leading.bottom, _height - GlassInputBar.gap);
    // The send button stays at the capsule's end, inset as far all round.
    expect(button.size, const Size.square(GlassInputBar.height - 8));
    expect(button.bottom, leading.bottom - 4);
  });
}
