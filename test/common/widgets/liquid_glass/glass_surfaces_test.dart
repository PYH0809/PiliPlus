import 'package:PiliPlus/common/widgets/liquid_glass/glass_panel.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(GlassSurfaces.install);

  for (final brightness in Brightness.values) {
    testWidgets('an alert is on FlClash\'s alert glass and rim, '
        '${brightness.name}', (tester) async {
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AlertDialog(title: Text('标题'), content: Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final panel = tester.widget<GlassPanel>(find.byType(GlassPanel));
      expect(panel.style, LiquidGlassStyle.alert(theme.colorScheme));
      expect(panel.rim, LiquidGlassRim.alert(theme.colorScheme));
      expect(panel.radius, 34);
    });
  }
}
