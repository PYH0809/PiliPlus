import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/vote/reply_vote_item.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/widgets/detail_glass.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class VideoReplyPanel extends StatefulWidget {
  const VideoReplyPanel({
    super.key,
    this.replyLevel = 1,
    required this.heroTag,
    required this.isNested,
  });

  final int replyLevel;
  final String heroTag;
  final bool isNested;

  @override
  State<VideoReplyPanel> createState() => _VideoReplyPanelState();
}

class _VideoReplyPanelState extends State<VideoReplyPanel>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        FabMixin {
  late ColorScheme colorScheme;
  late VideoReplyController _videoReplyController;

  String get heroTag => widget.heroTag;

  /// Whether the sort row and the button to comment are liquid glass.
  late final bool _glass = GlassSurfaces.installed;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _videoReplyController = Get.find<VideoReplyController>(tag: heroTag);
    if (_videoReplyController.loadingState.value is Loading) {
      _videoReplyController.queryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoReplyController.didChangeDependencies(context);
    colorScheme = ColorScheme.of(context);
    bottom = MediaQuery.viewPaddingOf(context).bottom;
  }

  late double bottom;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return fabAnimWrapper(
      child: refreshIndicator(
        onRefresh: _videoReplyController.onRefresh,
        isClampingScrollPhysics: widget.isNested,
        child: ScaffoldLayout(
          body: CustomScrollView(
            controller: widget.isNested
                ? null
                : _videoReplyController.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            key: const PageStorageKey(_VideoReplyPanelState),
            slivers: [
              if (_glass)
                SliverFloatingHeaderWidget(
                  backgroundColor: colorScheme.surface,
                  child: _glassSortRow(),
                )
              else
                SliverFloatingHeaderWidget(
                  backgroundColor: colorScheme.surface,
                  child: Padding(
                    padding: const .fromLTRB(12, 2.5, 6, 2.5),
                    child: Obx(() {
                      final sortType = _videoReplyController.sortType.value;
                      return Row(
                        mainAxisAlignment: .spaceBetween,
                        children: [
                          Text(
                            sortType.desc,
                            style: const TextStyle(fontSize: 13),
                          ),
                          TextButton.icon(
                            style: Style.buttonStyle,
                            onPressed: _videoReplyController.queryBySort,
                            icon: Icon(
                              Icons.sort,
                              size: 16,
                              color: colorScheme.secondary,
                            ),
                            label: Text(
                              sortType.descShort,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              Obx(() => _buildBody(_videoReplyController.loadingState.value)),
            ],
          ),
          fab: SlideTransition(
            position: fabAnimation,
            child: Padding(
              // On glass, room above for the drop's shadow, which then slides
              // out of sight with it.
              padding: .only(
                top: _glass ? 24 : 0,
                right: kFloatingActionButtonMargin,
                bottom: kFloatingActionButtonMargin + bottom,
              ),
              child: _glass
                  ? GlassReplyFab(onTap: _onReply)
                  : FloatingActionButton(
                      heroTag: null,
                      onPressed: _onReply,
                      tooltip: '发表评论',
                      child: const Icon(Icons.reply),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _onReply() {
    feedBack();
    _videoReplyController.onReply(
      null,
      oid: _videoReplyController.aid,
      replyType: _videoReplyController.videoType.replyType,
      mentionItem: _videoReplyController.mentionItem,
    );
  }

  Widget _glassSortRow() => Obx(() {
    final sortType = _videoReplyController.sortType.value;
    return GlassReplySortRow(
      desc: sortType.desc,
      label: sortType.descShort,
      onSort: _videoReplyController.queryBySort,
    );
  });

  Widget _buildBody(LoadingState<List<ReplyInfo>?> loadingState) {
    switch (loadingState) {
      case Loading():
        return const SliverPrototypeExtentList(
          prototypeItem: VideoReplySkeleton(),
          delegate: SliverSingleChildDelegate(
            count: 5,
            child: VideoReplySkeleton(),
          ),
        );
      case Success(:final response):
        if (response != null && response.isNotEmpty) {
          var count = response.length + 1;
          final voteCard = _videoReplyController.voteCard;
          final hasVote = voteCard != null;
          if (hasVote) {
            count++;
          }
          return SliverList.builder(
            itemBuilder: (context, index) {
              if (hasVote) {
                if (index == 0) {
                  return buildVoteCard(context, colorScheme, voteCard);
                } else {
                  index--;
                }
              }
              if (index == response.length) {
                _videoReplyController.onLoadMore();
                return Container(
                  height: 125,
                  alignment: .center,
                  margin: .only(bottom: bottom),
                  child: Text(
                    _videoReplyController.isEnd ? '没有更多了' : '加载中...',
                    textAlign: .center,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                );
              } else {
                final item = response[index];
                final child = ReplyItemGrpc(
                  replyItem: item,
                  replyLevel: widget.replyLevel,
                  replyReply: _videoReplyController.replyReply,
                  onReply: _videoReplyController.onReply,
                  onDelete: (item, subIndex) =>
                      _videoReplyController.onRemove(index, item, subIndex),
                  upMid: _videoReplyController.upMid,
                  getTag: () => heroTag,
                  onCheckReply: _videoReplyController.onCheckReply,
                  onToggleTop: (item) => _videoReplyController.onToggleTop(
                    item,
                    index,
                    _videoReplyController.aid,
                    _videoReplyController.videoType.replyType,
                  ),
                );
                if (item.id == _videoReplyController.targetRootRpId) {
                  return _videoReplyController.colorAnimWrapper(
                    colorScheme,
                    child,
                  );
                }
                return child;
              }
            },
            itemCount: count,
          );
        }

        final child = HttpError(
          errMsg: '还没有评论',
          onReload: _videoReplyController.onReload,
        );
        if (_videoReplyController.voteCard case final voteCard?) {
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: buildVoteCard(context, colorScheme, voteCard),
              ),
              child,
            ],
          );
        }
        return child;
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: _videoReplyController.onReload,
        );
    }
  }
}
