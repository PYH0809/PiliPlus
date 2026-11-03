import 'package:PiliPlus/models/dynamics/article_content_model.dart';
import 'package:PiliPlus/pages/article/widgets/opus_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

ArticleContentModel _paragraph(Map<String, dynamic> rich) =>
    ArticleContentModel.fromJson({
      'para_type': 1,
      'text': {
        'nodes': [
          {'type': 'TEXT_NODE_TYPE_RICH', 'rich': rich},
        ],
      },
    });

void main() {
  testWidgets('a vote or a lottery with its orig_text only shows it, not '
      '"null"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              OpusContent(
                opus: [
                  _paragraph({
                    'type': 'RICH_TEXT_NODE_TYPE_VOTE',
                    'orig_text': '投票：选哪个',
                    'rid': '1',
                  }),
                  _paragraph({
                    'type': 'RICH_TEXT_NODE_TYPE_LOTTERY',
                    'orig_text': '互动抽奖',
                  }),
                ],
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

    expect(find.textContaining('投票：选哪个', findRichText: true), findsOneWidget);
    expect(find.textContaining('互动抽奖', findRichText: true), findsOneWidget);
    expect(find.textContaining('null', findRichText: true), findsNothing);
  });
}
