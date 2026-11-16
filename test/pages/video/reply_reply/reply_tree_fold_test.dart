import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show FoldCard, FoldListResp, MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart'
    show FeedPagination, FeedPaginationReply;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/video/reply_reply/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The replies of a thread, with its folded ones in pages and no network.
class _Thread extends VideoReplyReplyController {
  _Thread(this.pages)
    : super(
        hasRoot: false,
        id: null,
        oid: 1,
        rpid: 1,
        dialog: null,
        replyType: 1,
      );

  final List<FoldListResp> pages;
  int folds = 0;

  @override
  Future<LoadingState<MainListReply>> customGetData() async =>
      const Error(null);

  @override
  Future<LoadingState<FoldListResp>> requestFoldList(
    FeedPagination pagination,
  ) async => Success(pages[folds++]);
}

// A reply to the thread's first floor, 1, which the list leaves out.
ReplyInfo _reply(int id) => ReplyInfo(
  id: Int64(id),
  root: Int64(1),
  parent: Int64(1),
  dialog: Int64(id),
);

FoldListResp _foldPage(List<int> ids, {String next = ''}) => FoldListResp(
  replies: ids.map(_reply),
  paginationReply: FeedPaginationReply(nextOffset: next),
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-reply-tree-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('the reply tree waits for every page of folded replies', (
    tester,
  ) async {
    final thread =
        _Thread([
            _foldPage([3, 4], next: 'more'),
            _foldPage([5]),
          ])
          ..loadingState.value = Success([_reply(2)])
          ..isEnd = true
          ..foldCard = FoldCard(foldPagination: FeedPagination(offset: 'fold'))
          ..nextReplyRound();
    await tester.runAsync(thread.onLoadMore);
    // The second page comes after the next round's wait.
    expect(thread.replyTree.value, isNull);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(thread.onLoadMore);

    expect(thread.folds, 2);
    expect(thread.replyTree.value, isNotNull);
    expect(
      thread.loadingState.value.data!.map((e) => e.id.toInt()),
      [2, 3, 4, 5],
    );
  });
}
