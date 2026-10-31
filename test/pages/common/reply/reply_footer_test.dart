import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show FoldCard, MainListReply;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart' show FeedPagination;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply/fold/reply_fold_mixin.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:PiliPlus/pages/common/reply/reply_footer_mixin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Replies without the network: notes where they would load on from.
class _Replies extends ReplyController<MainListReply>
    with BaseReplyFoldMixin<MainListReply> {
  int folds = 0;
  int mains = 0;

  @override
  int get oid => 1;

  @override
  int get replyType => 1;

  @override
  dynamic get sourceId => null;

  @override
  Future<LoadingState<MainListReply>> customGetData() async =>
      const Error(null);

  @override
  Future<void> loadFoldList() async => folds++;

  @override
  Future<void> onLoadMore() async => mains++;
}

class _Page extends StatefulWidget {
  const _Page(this.replies, {required this.empty});

  final _Replies replies;
  final bool empty;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page>
    with ReplyFooterMixin<_Page, MainListReply> {
  @override
  _Replies get controller => widget.replies;

  @override
  ColorScheme get colorScheme => ColorScheme.of(context);

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      if (widget.empty)
        emptyWidget()
      else
        SliverToBoxAdapter(child: buildFooter()),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Replies replies, {
  bool empty = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: _Page(replies, empty: empty)),
  ),
);

void main() {
  testWidgets('with every reply folded, the empty list shows the way to them, '
      'not that there are none', (tester) async {
    final replies = _Replies()..foldCard = FoldCard(bottomText: '查看折叠评论');
    await _pump(tester, replies, empty: true);

    expect(find.text('还没有评论'), findsNothing);
    await tester.tap(find.text('查看折叠评论'));
    expect(replies.folds, 1);
  });

  testWidgets('more folded replies than a page load on at the end, not the '
      'main list\'s spent cursor', (tester) async {
    final replies = _Replies()
      ..isEnd = true
      ..foldNext = FeedPagination(offset: 'next');
    await _pump(tester, replies);

    expect(replies.folds, 1);
    expect(replies.mains, 0);
    expect(find.text('加载中...'), findsOneWidget);
    expect(find.text('没有更多了'), findsNothing);
  });

  testWidgets('a page of folded replies all filtered out, the empty list '
      'loads on with them', (tester) async {
    final replies = _Replies()
      ..isEnd = true
      ..foldNext = FeedPagination(offset: 'next');
    await _pump(tester, replies, empty: true);

    expect(replies.folds, 1);
    expect(find.text('还没有评论'), findsNothing);
    expect(find.text('加载中...'), findsOneWidget);
  });

  testWidgets('all folded replies in, the end is the end', (tester) async {
    final replies = _Replies()..isEnd = true;
    await _pump(tester, replies);

    expect(find.text('没有更多了'), findsOneWidget);
  });
}
