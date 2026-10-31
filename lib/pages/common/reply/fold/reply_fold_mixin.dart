import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show FoldCard, MainListReply, MixedCard, ReplyInfo;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart' show FeedPagination;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

mixin BaseReplyFoldMixin<R> on ReplyController<R> {
  FoldCard? foldCard;

  /// Where the folded replies go on, once a page of them has come and more
  /// remain: the footer loads on from it, as it does the main list.
  FeedPagination? foldNext;

  void getFoldCard(List<MixedCard> mixedCards) {
    if (mixedCards.isNotEmpty) {
      foldCard = mixedCards.firstWhereOrNull((e) => e.type == .FOLD)?.fold;
    }
  }

  Future<void> loadFoldList() async {
    final pagination = foldNext ?? foldCard?.foldPagination;
    if (isLoading || pagination == null) return;
    final first = foldNext == null;
    isLoading = true;
    try {
      final res = await ReplyGrpc.foldList(
        oid: oid,
        type: replyType,
        pagination: pagination,
      );
      if (isClosed) return;
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
      }
    } catch (e) {
      if (kDebugMode) rethrow;
      SmartDialog.showToast(e.toString());
    } finally {
      isLoading = false;
    }
  }

  @override
  Future<void> onRefresh() {
    foldCard = null;
    foldNext = null;
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
