import 'dart:async';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show FoldCard, FoldListResp, MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart'
    show FeedPagination, FeedPaginationReply;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply/fold/reply_fold_mixin.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:PiliPlus/pages/common/reply/reply_footer_mixin.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
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

/// Replies whose pages come when the test has them come.
class _Loading extends ReplyController<MainListReply>
    with BaseReplyFoldMixin<MainListReply>, ReplyFoldMixin {
  final folds = <Completer<LoadingState<FoldListResp>>>[];
  final mains = <Completer<LoadingState<MainListReply>>>[];

  @override
  int get oid => 1;

  @override
  int get replyType => 1;

  @override
  dynamic get sourceId => null;

  @override
  Future<LoadingState<MainListReply>> customGetData() {
    mains.add(Completer());
    return mains.last.future;
  }

  @override
  Future<LoadingState<FoldListResp>> requestFoldList(
    FeedPagination pagination,
  ) {
    folds.add(Completer());
    return folds.last.future;
  }
}

ReplyInfo _reply(int id) => ReplyInfo(id: Int64(id));

FoldListResp _foldPage(List<int> ids, {String next = ''}) => FoldListResp(
  replies: ids.map(_reply),
  paginationReply: FeedPaginationReply(nextOffset: next),
);

class _Page extends StatefulWidget {
  const _Page(this.replies, {required this.empty});

  final BaseReplyFoldMixin<MainListReply> replies;
  final bool empty;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page>
    with ReplyFooterMixin<_Page, MainListReply> {
  @override
  BaseReplyFoldMixin<MainListReply> get controller => widget.replies;

  @override
  ColorScheme get colorScheme => ColorScheme.of(context);

  // As the reply pages, built again as the list changes.
  @override
  Widget build(BuildContext context) => Obx(() {
    controller.loadingState.value;
    return CustomScrollView(
      slivers: [
        if (widget.empty)
          emptyWidget()
        else
          SliverToBoxAdapter(child: buildFooter()),
      ],
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  BaseReplyFoldMixin<MainListReply> replies, {
  bool empty = false,
}) => tester.pumpWidget(
  MaterialApp(
    builder: FlutterSmartDialog.init(),
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

  test(
    'a refresh, as for another video, leaves a page of folded replies '
    'under way behind: it lands in neither list, and the new list loads',
    () async {
      final replies = _Loading()
        ..loadingState.value = Success([_reply(1)])
        ..foldNext = FeedPagination(offset: 'next');
      unawaited(replies.loadFoldList());

      unawaited(replies.onReload());
      expect(replies.mains, hasLength(1));

      // The old video's page comes, then the new video's list.
      replies.folds.single.complete(Success(_foldPage([2], next: 'more')));
      await pumpEventQueue();
      expect(replies.foldNext, isNull);
      replies.mains.single.complete(
        Success(MainListReply(replies: [_reply(3)])),
      );
      await pumpEventQueue();

      final list = (replies.loadingState.value as Success).response!;
      expect([for (final ReplyInfo reply in list) reply.id.toInt()], [3]);
      expect(replies.isLoading, isFalse);
    },
  );

  testWidgets('a page of folded replies that failed to come, with none '
      'shown, offers to try again', (tester) async {
    final replies = _Loading()
      ..loadingState.value = Success(List<ReplyInfo>.empty(growable: true))
      ..isEnd = true
      ..foldNext = FeedPagination(offset: 'next');
    await _pump(tester, replies, empty: true);
    expect(replies.folds, hasLength(1));

    replies.folds.single.complete(const Error('网络错误'));
    await tester.pump();
    expect(find.text('加载中...'), findsNothing);
    expect(replies.folds, hasLength(1));

    await tester.tap(find.text('加载失败，点击重试'));
    expect(replies.folds, hasLength(2));
    replies.folds.last.complete(Success(_foldPage([4])));
    await tester.pump();
    expect(replies.foldNext, isNull);
    expect(find.text('加载失败，点击重试'), findsNothing);
    // The failure's toast gone.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
