import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/pages/search/widgets/search_glass_header.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _statusBar = 24.0;

/// A list starting below the header, as the search page's and each result
/// tab's.
class _List extends StatelessWidget {
  const _List();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        HeaderOverlayInset.sliver(context),
        SliverList.builder(
          itemCount: 40,
          itemBuilder: (context, index) =>
              SizedBox(key: ValueKey('item$index'), height: 80),
        ),
      ],
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  void Function(GlassMorphButtonState button)? onFieldTap,
  Widget? trailing,
  double extent = SearchGlassBar.extent,
  Widget? below,
}) async {
  tester.view
    ..physicalSize = const Size(412, 800)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: _statusBar)
    ..viewPadding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
  final page = SearchGlassScaffold(
    extent: extent,
    header: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchGlassBar(
          onFieldTap: onFieldTap,
          trailing: trailing,
          field: const Center(child: Text('原神')),
        ),
        ?below,
      ],
    ),
    content: const _List(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (context) => page),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a round back button, then the capsule to the end', (
    tester,
  ) async {
    await _pump(tester);
    final back = tester.getRect(find.byTooltip('返回'));
    expect(back, const Rect.fromLTWH(14, _statusBar + 6, 40, 40));
    final capsule = tester.getRect(find.byType(LiquidGlass).at(1));
    expect(capsule.left, back.right + 8);
    expect(capsule.right, 412 - 14);
    expect(capsule.top, back.top);
    expect(capsule.height, 40);
  });

  testWidgets('a trailing button stands 8 after the capsule, at the end', (
    tester,
  ) async {
    await _pump(
      tester,
      trailing: const SizedBox.square(
        key: ValueKey('search'),
        dimension: 40,
      ),
    );
    final search = tester.getRect(find.byKey(const ValueKey('search')));
    expect(search.right, 412 - 14);
    expect(search.top, _statusBar + 6);
    final capsule = tester.getRect(find.byType(LiquidGlass).at(1));
    expect(capsule.right, search.left - 8);
  });

  testWidgets('the list starts below the bar and scrolls under it', (
    tester,
  ) async {
    await _pump(tester);
    final first = find.byKey(const ValueKey('item0'));
    expect(tester.getTopLeft(first).dy, _statusBar + SearchGlassBar.extent);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
    await tester.pump();
    // Under the bar, though not under the status bar.
    expect(
      tester.getTopLeft(first).dy,
      _statusBar + SearchGlassBar.extent - 100,
    );
    expect(
      tester.getTopLeft(find.byType(CustomScrollView)).dy,
      _statusBar,
    );
  });

  testWidgets('a taller header pushes the list down as far', (tester) async {
    const tabs = 2.0 + 40 + 4;
    await _pump(
      tester,
      extent: SearchGlassBar.extent + tabs,
      below: const SizedBox(height: tabs),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('item0'))).dy,
      _statusBar + SearchGlassBar.extent + tabs,
    );
  });

  testWidgets('the back button goes back', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(SearchGlassBar), findsNothing);
  });

  testWidgets('with onFieldTap the capsule is a button pages grow out of', (
    tester,
  ) async {
    final taps = <GlassMorphButtonState>[];
    await _pump(tester, onFieldTap: taps.add);
    final button = find.ancestor(
      of: find.text('原神'),
      matching: find.byType(GlassMorphButton),
    );
    expect(button, findsOneWidget);
    await tester.tap(find.text('原神'));
    await tester.pump();
    expect(taps, [tester.state<GlassMorphButtonState>(button)]);
  });

  testWidgets('the status bar reads as over the surface', (tester) async {
    await _pump(tester);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
    );
    expect(region.value.statusBarIconBrightness, Brightness.dark);
    expect(region.value.statusBarColor, Colors.transparent);
  });
}
