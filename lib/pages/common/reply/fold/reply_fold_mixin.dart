import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show FoldCard, FoldListResp, MainListReply, MixedCard, ReplyInfo;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart' show FeedPagination;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

mixin BaseReplyFoldMixin<R> on ReplyController<R> {
  FoldCard? foldCard;

  /// Where the folded replies go on, once a page of them has come and more
  /// remain: the footer loads on from it, as it does the main list.
  FeedPagination? foldNext;

  /// Whether the last page of folded replies failed to come: the footer
  /// offers to try again, rather than trying again on every build.
  bool foldFailed = false;

  // The folded replies' load under way, which a refresh, as for another
  // video, leaves behind.
  Object? _foldLoad;

  @visibleForTesting
  Future<LoadingState<FoldListResp>> requestFoldList(
    FeedPagination pagination,
  ) => ReplyGrpc.foldList(oid: oid, type: replyType, pagination: pagination);

  void getFoldCard(List<MixedCard> mixedCards) {
    if (mixedCards.isNotEmpty) {
      foldCard = mixedCards.firstWhereOrNull((e) => e.type == .FOLD)?.fold;
    }
  }

  Future<void> loadFoldList() async {
    final pagination = foldNext ?? foldCard?.foldPagination;
    if (isLoading || pagination == null) return;
    final first = foldNext == null;
    final load = _foldLoad = Object();
    isLoading = true;
    foldFailed = false;
    try {
      final res = await requestFoldList(pagination);
      if (isClosed || !identical(load, _foldLoad)) return;
      if (res case Success(:final response)) {
        foldCard = null;
        final next = response.paginationReply.nextOffset;
        foldNext = next.isEmpty ? null : FeedPagination(offset: next);
        if (loadingState.value case Success(response: final replies?)) {
          replies.addAll(response.replies);
          loadingState.refresh();
        } else {
          loadingState.value = Success(response.replies);
        }
        if (first && response.hasTitle()) {
          SmartDialog.showToast(response.title);
        }
      } else {
        res.toast();
        _foldFailed();
      }
    } catch (e) {
      if (kDebugMode) rethrow;
      SmartDialog.showToast(e.toString());
      if (identical(load, _foldLoad)) _foldFailed();
    } finally {
      if (identical(load, _foldLoad)) {
        _foldLoad = null;
        isLoading = false;
      }
    }
  }

  void _foldFailed() {
    foldFailed = true;
    loadingState.refresh();
  }

  @override
  Future<void> onRefresh() {
    foldCard = null;
    foldNext = null;
    foldFailed = false;
    // The list goes on without the load under way: its page would land in
    // the new one, and it holds the list's own load back.
    if (_foldLoad != null) {
      _foldLoad = null;
      isLoading = false;
    }
    return super.onRefresh();
  }
}

mixin ReplyFoldMixin on BaseReplyFoldMixin<MainListReply> {
  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    getFoldCard(response.mixedCards);
    return response.replies;
  }
}
