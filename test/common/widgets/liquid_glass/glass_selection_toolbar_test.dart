import 'package:PiliPlus/common/widgets/liquid_glass/glass_panel.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(GlassSurfaces.install);

  for (final brightness in Brightness.values) {
    testWidgets('the text selection toolbar is on FlClash\'s edit menu glass, '
        'with no rim, ${brightness.name}', (tester) async {
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: TextSelectionToolbar(
              anchorAbove: const Offset(200, 200),
              anchorBelow: const Offset(200, 240),
              children: [
                TextSelectionToolbarTextButton(
                  padding: TextSelectionToolbarTextButton.getPadding(0, 1),
                  onPressed: () {},
                  child: const Text('复制'),
                ),
              ],
            ),
          ),
        ),
      );

      final panel = tester.widget<GlassPanel>(find.byType(GlassPanel));
      expect(panel.style, LiquidGlassStyle.editMenu(theme.colorScheme));
      expect(panel.rim, isNull);
    });
  }

  testWidgets('the toolbar\'s labels stay white under the pure black theme, '
      'which dims onSurface', (tester) async {
    final theme = ThemeUtils.darkenTheme(
      ThemeData(brightness: Brightness.dark),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: TextSelectionToolbar(
            anchorAbove: const Offset(200, 200),
            anchorBelow: const Offset(200, 240),
            children: [
              TextSelectionToolbarTextButton(
                padding: TextSelectionToolbarTextButton.getPadding(0, 1),
                onPressed: () {},
                child: const Text('复制'),
              ),
            ],
          ),
        ),
      ),
    );

    final style = DefaultTextStyle.of(tester.element(find.text('复制'))).style;
    expect(style.color, Colors.white);
  });
}
