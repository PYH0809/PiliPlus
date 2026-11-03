import 'package:PiliPlus/models/dynamics/article_content_model.dart';
import 'package:PiliPlus/pages/article/widgets/opus_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

ArticleContentModel _paragraph(Map<String, dynamic> word) =>
    ArticleContentModel.fromJson({
      'para_type': 1,
      'text': {
        'nodes': [
          {'type': 'TEXT_NODE_TYPE_WORD', 'word': word},
        ],
      },
    });

double? _fontSizeOf(WidgetTester tester, String words) {
  final span = tester
      .widgetList<RichText>(find.byType(RichText))
      .map((e) => e.text)
      .expand((e) {
        final spans = <TextSpan>[];
        e.visitChildren((s) {
          if (s is TextSpan && s.text == words) spans.add(s);
          return true;
        });
        return spans;
      })
      .single;
  return span.style?.fontSize;
}

void main() {
  Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> words) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                OpusContent(
                  opus: [for (final w in words) _paragraph(w)],
                  images: () => const [],
                  maxWidth: 400,
                  opusId: '1',
                  reverse: false,
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('a styled word keeps its own size when the style sets none', (
    tester,
  ) async {
    await pump(tester, [
      {
        'words': 'sized',
        'font_size': 24,
        'style': {'bold': true},
      },
      {
        'words': 'small',
        'font_level': 'small',
        'style': {'italic': true},
      },
    ]);

    expect(_fontSizeOf(tester, 'sized'), 24);
    expect(_fontSizeOf(tester, 'small'), 13);
  });

  testWidgets("a style's own level still sets the size", (tester) async {
    await pump(tester, [
      {
        'words': 'large',
        'font_size': 16,
        'style': {'font_level': 'xxLarge'},
      },
      {'words': 'plain'},
    ]);

    expect(_fontSizeOf(tester, 'large'), 24);
    expect(_fontSizeOf(tester, 'plain'), 16);
  });
}
