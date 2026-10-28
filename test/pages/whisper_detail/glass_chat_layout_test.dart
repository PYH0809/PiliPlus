import 'package:PiliPlus/common/widgets/flutter/chat_list_view.dart';
import 'package:PiliPlus/pages/whisper_detail/widget/glass_chat_layout.dart';
import 'package:PiliPlus/pages/whisper_detail/widget/glass_input_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _width = 412.0;
const _height = 800.0;

/// A chat as the whisper page lays it out on glass: [count] messages 60 tall
/// under a bar [barHeight] tall, the keyboard's room under it included.
class _Chat extends StatelessWidget {
  const _Chat({
    required this.inset,
    required this.barHeight,
    this.count = 30,
    this.controller,
    this.onMessagesTouched,
  });

  final ChatBarInset inset;
  final double barHeight;
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
      bar: SizedBox(
        key: const ValueKey('bar'),
        height: barHeight,
        child: const Row(
          children: [
            SizedBox(width: 40),
            Spacer(),
            SizedBox(width: 40),
          ],
        ),
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
    for (final barHeight in [56.0, 400.0, 230.0, 56.0]) {
      // One frame, as when the keyboard moves the bar.
      await _pump(tester, _Chat(inset: inset, barHeight: barHeight));
      expect(inset.value, barHeight);
      final barTop = tester.getTopLeft(find.byKey(const ValueKey('bar'))).dy;
      expect(barTop, _height - barHeight);
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
      _Chat(inset: inset, barHeight: 56, controller: controller),
    );
    controller.jumpTo(200);
    await tester.pump();
    // The list spans the page, so a message scrolled down past the bar's top
    // is still laid out there, for the glass to show through it.
    expect(tester.getSize(find.byType(Scrollable)).height, _height);
    final message = tester.getRect(find.byKey(const ValueKey(2)));
    expect(message.bottom, greaterThan(_height - 56));
    expect(message.top, lessThan(_height));
  });

  testWidgets('a short chat still starts at the top', (tester) async {
    final inset = ChatBarInset();
    addTearDown(inset.dispose);
    await _pump(tester, _Chat(inset: inset, barHeight: 56, count: 2));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(1))).dy,
      kChatListPadding,
    );
  });

  testWidgets('touches on the bar, between its panes too, stay its own', (
    tester,
  ) async {
    final inset = ChatBarInset();
    addTearDown(inset.dispose);
    var touched = 0;
    await _pump(
      tester,
      _Chat(inset: inset, barHeight: 56, onMessagesTouched: () => touched++),
    );
    await tester.tapAt(const Offset(_width / 2, _height - 28));
    expect(touched, 0);
    await tester.tapAt(const Offset(_width / 2, _height / 2));
    expect(touched, 1);
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
