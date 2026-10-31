import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show FoldCard;
import 'package:PiliPlus/pages/common/reply/fold/reply_fold_mixin.dart';
import 'package:material_ui/material_ui.dart';

mixin ReplyFooterMixin<T extends StatefulWidget, R> on State<T> {
  late EdgeInsets padding;
  ColorScheme get colorScheme;
  BaseReplyFoldMixin<R> get controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  Widget buildFooter() {
    final fold = controller.foldCard;
    if (fold != null) return _buildFoldItem(fold);

    // More folded replies than a page: on with them, as with the main list,
    // whose cursor is done with by then.
    if (controller.foldNext != null) return _buildFoldNext();

    controller.onLoadMore();
    return _buildEndItem();
  }

  Widget _buildFoldNext() {
    if (controller.foldFailed) return _buildTapItem('加载失败，点击重试');
    controller.loadFoldList();
    return _buildEndItem(loading: true);
  }

  Widget _buildFoldItem(FoldCard fold) => _buildTapItem(fold.bottomText);

  Widget _buildTapItem(String text) {
    return Container(
      height: 125,
      alignment: .topCenter,
      margin: .only(bottom: padding.bottom),
      child: Material(
        type: .transparency,
        child: InkWell(
          onTap: controller.loadFoldList,
          child: SizedBox(
            width: .infinity,
            child: Padding(
              padding: const .symmetric(vertical: 12),
              child: Text(
                text,
                textAlign: .center,
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndItem({bool loading = false}) {
    return Container(
      height: 125,
      alignment: .center,
      margin: .only(bottom: padding.bottom),
      child: Text(
        controller.isEnd && !loading ? '没有更多了' : '加载中...',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: colorScheme.outline),
      ),
    );
  }

  Widget emptyWidget() {
    // Every reply folded, as left out of the main list: the way to them,
    // not that there are none.
    if (controller.foldCard case final fold?) {
      return SliverToBoxAdapter(child: _buildFoldItem(fold));
    }
    // A page of them all filtered out, more to come: on with them.
    if (controller.foldNext != null) {
      return SliverToBoxAdapter(child: _buildFoldNext());
    }
    return HttpError(
      errMsg: '还没有评论',
      onReload: controller.onReload,
    );
  }
}
