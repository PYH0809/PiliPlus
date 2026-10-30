import 'dart:async';
import 'dart:math';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/keep_alive_wrapper.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/menu_entries.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarScrollPhysics;
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class EpisodePanel extends CommonSlidePage {
  const EpisodePanel({
    super.key,
    super.enableSlide,
    required this.ugcIntroController,
    required this.heroTag,
    required this.type,
    // required this.count,
    // required this.name,
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.cover,
    this.showTitle = true,
    required this.list,
    this.seasonId,
    this.initialTabIndex = 0,
    this.isSupportReverse,
    this.isReversed,
    this.onReverse,
    required this.onChangeEpisode,
    this.onClose,
  }) : assert(type == EpisodeType.pgc || ugcIntroController != null);

  final UgcIntroController? ugcIntroController;
  final String heroTag;
  final EpisodeType type;
  // final int count;
  // final String name;
  final int? aid;
  final String bvid;
  final int cid;
  final String? cover;
  final bool showTitle;
  final List list;
  final int? seasonId;
  final int initialTabIndex;
  final bool? isSupportReverse;
  final bool? isReversed;
  final Future<bool> Function(ugc.BaseEpisodeItem) onChangeEpisode;
  final VoidCallback? onReverse;
  final VoidCallback? onClose;

  @override
  State<EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<EpisodePanel>
    with TickerProviderStateMixin, CommonSlideMixin {
  // tab
  late final TabController _tabController;
  late final RxInt _currentTabIndex = _tabController.index.obs;

  late final showTitle = widget.showTitle;

  List<ugc.BaseEpisodeItem> get _getCurrEpisodes =>
      widget.type == EpisodeType.season
      ? widget.list[_currentTabIndex.value].episodes
      : widget.list[_currentTabIndex.value];

  // item
  late int _currentItemIndex;
  int get _findCurrentItemIndex => max(
    0,
    _getCurrEpisodes.indexWhere((item) => item.cid == widget.cid),
  );

  late final List<bool> _isReversed;
  late final List<ScrollController> _itemScrollController;

  // fav
  Rx<LoadingState<bool>>? _favState;

  void listener() {
    _currentTabIndex.value = _tabController.index;
  }

  @override
  void didUpdateWidget(EpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (showTitle) {
      return;
    }

    @pragma('vm:notify-debugger-on-exception')
    void jumpToCurrent() {
      final newItemIndex = _findCurrentItemIndex;
      if (_currentItemIndex != newItemIndex) {
        _currentItemIndex = newItemIndex;
        try {
          _itemScrollController[_currentTabIndex.value].jumpTo(
            _calcItemOffset(newItemIndex),
          );
        } catch (e, s) {
          Utils.reportError(e, s);
        }
      }
    }

    // jump to current
    if (_currentTabIndex.value != widget.initialTabIndex) {
      _tabController.animateTo(
        widget.initialTabIndex,
        duration: const Duration(milliseconds: 200),
      );
      Timer(const Duration(milliseconds: 300), jumpToCurrent);
    } else {
      jumpToCurrent();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      initialIndex: widget.initialTabIndex,
      length: widget.list.length,
      vsync: this,
    )..addListener(listener);

    _currentItemIndex = _findCurrentItemIndex;
    _itemScrollController = List.generate(
      widget.list.length,
      (i) => ScrollController(
        initialScrollOffset: i == widget.initialTabIndex
            ? _currentItemIndex == 0
                  ? 0
                  : _calcItemOffset(_currentItemIndex)
            : 0,
      ),
      growable: false,
    );
    _isReversed = List.filled(widget.list.length, false);

    if (widget.type == EpisodeType.season && Accounts.main.isLogin) {
      final favState =
          widget.ugcIntroController?.seasonFavState[widget.seasonId];
      if (favState != null) {
        _favState = Success(favState).obs;
      } else {
        _favState = LoadingState<bool>.loading().obs;
        VideoHttp.videoRelation(bvid: widget.bvid).then(
          (result) {
            if (!mounted) return;
            if (result case Success(:final response)) {
              final seasonFav = response.seasonFav ?? false;
              _favState!.value = Success(seasonFav);
              widget.ugcIntroController?.seasonFavState[widget.seasonId] =
                  seasonFav;
            }
          },
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(listener)
      ..dispose();
    _favState?.close();
    for (final e in _itemScrollController) {
      e.dispose();
    }
    super.dispose();
  }

  late final _isMulti =
      widget.type == EpisodeType.season && widget.list.length > 1;

  // On glass the sheet's bar floats over its list, but not where the panel
  // is glass already, as over the video, since glass never lies on glass.
  late final bool _floatingBar =
      showTitle && GlassAppBar.enabled && !GlassSurfaces.onGlass(context);

  /// How far the floating bar covers the top of the list.
  double get _barInset =>
      _floatingBar ? _buildGlassBar().preferredSize.height : 0;

  @override
  Widget buildPage(ThemeData theme) {
    if (_floatingBar) {
      return Material(
        color: theme.colorScheme.surface,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: GlassAppBarBody(
            appBar: _buildGlassBar(),
            body: enableSlide ? slideList(theme) : buildList(theme),
          ),
        ),
      );
    }
    return Material(
      color: showTitle ? theme.colorScheme.surface : null,
      type: showTitle ? MaterialType.canvas : MaterialType.transparency,
      child: Column(
        children: [
          _buildToolbar(theme),
          if (_isMulti)
            TabBar(
              controller: _tabController,
              padding: const EdgeInsets.only(right: 60),
              isScrollable: true,
              tabs: widget.list.map((item) => Tab(text: item.title)).toList(),
              dividerHeight: 1,
              dividerColor: theme.dividerColor.withValues(alpha: 0.1),
            ),
          Expanded(child: enableSlide ? slideList(theme) : buildList(theme)),
        ],
      ),
    );
  }

  @override
  Widget buildList(ThemeData theme) {
    if (_isMulti) {
      return TabBarView(
        controller: _tabController,
        physics: tabBarScrollPhysics,
        horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
        children: List.generate(
          widget.list.length,
          (index) => _buildBody(
            theme,
            index,
            widget.list[index].episodes,
          ),
        ),
      );
    }
    return _buildBody(theme, 0, _getCurrEpisodes);
  }

  double _calcItemOffset(int index) {
    if (showTitle) {
      final episodes = _getCurrEpisodes;
      double offset = 0;
      for (var i = 0; i < index; i++) {
        offset += _calcItemHeight(episodes[i]);
      }
      return offset + 7;
    } else {
      return index * 112 + 7;
    }
  }

  double _calcItemHeight(ugc.BaseEpisodeItem episode) {
    if (episode is ugc.EpisodeItem && episode.pages!.length > 1) {
      return 167; // 110 + 2 + 10 + 45
    }
    return 112;
  }

  Widget _buildBody(
    ThemeData theme,
    int tabIndex,
    List<ugc.BaseEpisodeItem> episodes,
  ) {
    final isCurrTab = tabIndex == widget.initialTabIndex;
    return KeepAliveWrapper(
      child: CustomScrollView(
        reverse: _isReversed[tabIndex],
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _itemScrollController[tabIndex],
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: 7 + _barInset,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
            ),
            sliver: showTitle
                ? SliverVariedExtentList.builder(
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrItem = isCurrTab
                          ? index == _currentItemIndex
                          : false;
                      Widget episodeItem = _buildEpisodeItem(
                        theme: theme,
                        episode: episode,
                        index: index,
                        length: episodes.length,
                        isCurrentIndex: isCurrItem,
                      );
                      if (episode is ugc.EpisodeItem &&
                          episode.pages!.length > 1) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            episodeItem, // 110
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ), // 10
                              child: PagesPanel(
                                // 45
                                list: isCurrTab && isCurrItem
                                    ? null
                                    : episode.pages,
                                cover: episode.arc?.pic,
                                heroTag: widget.heroTag,
                                ugcIntroController: widget.ugcIntroController!,
                                bvid:
                                    episode.bvid ?? IdUtils.av2bv(episode.aid!),
                              ),
                            ),
                          ],
                        );
                      }
                      return episodeItem;
                    },
                    itemExtentBuilder: (index, _) =>
                        _calcItemHeight(episodes[index]),
                  )
                : SliverFixedExtentList.builder(
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrItem = isCurrTab
                          ? index == _currentItemIndex
                          : false;
                      return _buildEpisodeItem(
                        theme: theme,
                        episode: episode,
                        index: index,
                        length: episodes.length,
                        isCurrentIndex: isCurrItem,
                      );
                    },
                    itemExtent: 112,
                  ),
          ),
        ],
      ),
    );
  }

  late final int? vipStatus = Pref.userInfoCache?.vipStatus;
  Widget _buildEpisodeItem({
    required ThemeData theme,
    required ugc.BaseEpisodeItem episode,
    required int index,
    required int length,
    required bool isCurrentIndex,
  }) {
    late String title;
    String? cover;
    String? bvid;
    num? duration;
    int? pubdate;
    int? view;
    int? danmaku;
    bool? isCharging;
    bool? cacheWidth;

    switch (episode) {
      case Part part:
        cover = part.firstFrame ?? widget.cover;
        title = part.part!;
        duration = part.duration;
        pubdate = part.ctime;
        cacheWidth = part.dimension?.cacheWidth;
        break;
      case ugc.EpisodeItem item:
        title = item.title!;
        bvid = item.bvid;
        if (item.arc case final arc?) {
          cover = arc.pic;
          duration = arc.duration;
          pubdate = arc.pubdate;
          if (arc.stat case final stat?) {
            view = stat.view;
            danmaku = stat.danmaku;
          }
          cacheWidth = arc.dimension?.cacheWidth;
        }
        if (item.attribute == 8) {
          isCharging = true;
        }
        break;
      case pgc.EpisodeItem item:
        bvid = item.bvid;
        title = item.showTitle ?? item.title!;
        cover = item.cover;
        if (item.from == 'pugv') {
          duration = item.duration;
          view = item.play;
        } else {
          duration = item.duration == null ? null : item.duration! ~/ 1000;
        }
        pubdate = item.pubTime;
        cacheWidth = item.dimension?.cacheWidth;
        break;
    }
    late final Color primary = theme.colorScheme.primary;

    void onLongPress() {
      if (cover?.isNotEmpty == true) {
        imageSaveDialog(title: title, cover: cover, bvid: bvid);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 110,
        child: Material(
          type: .transparency,
          child: InkWell(
            onTap: () {
              if (isCurrentIndex) return;
              if (episode.badge == "会员" &&
                  Accounts.mainEqVideo &&
                  vipStatus != 1) {
                SmartDialog.showToast('需要大会员');
                // return;
              }
              SmartDialog.showToast('切换到：$title');
              widget.onClose?.call();

              widget.onChangeEpisode(episode).then((res) {
                if (res) {
                  if (!showTitle) {
                    _currentItemIndex = index;
                  }
                  if (widget.type == EpisodeType.season) {
                    try {
                      Get.find<VideoDetailController>(
                        tag: widget.ugcIntroController!.heroTag,
                      ).seasonCid = episode.cid;
                    } catch (_) {
                      if (kDebugMode) rethrow;
                    }
                  }
                }
              });
            },
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            child: Padding(
              padding: const .symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                spacing: 10,
                children: [
                  if (cover?.isNotEmpty == true)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          src: cover,
                          width: 160,
                          height: 100,
                          cacheWidth: cacheWidth,
                        ),
                        if (duration != null && duration > 0)
                          PBadge(
                            text: DurationUtils.formatDuration(duration),
                            right: 6.0,
                            bottom: 6.0,
                            type: .gray,
                          ),
                        if (widget.type == .part)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const .symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: const .only(
                                  bottomLeft: .circular(4),
                                  topRight: Style.imgRadius,
                                ),
                              ),
                              child: Text(
                                (index + 1).toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          )
                        else if (isCharging == true)
                          const PBadge(
                            text: '充电专属',
                            top: 6,
                            right: 6,
                            type: .error,
                          )
                        else if (episode.badge != null)
                          PBadge(
                            text: episode.badge,
                            top: 6,
                            right: 6,
                            type: switch (episode.badge) {
                              '预告' => .gray,
                              '限免' => .free,
                              _ => .primary,
                            },
                          ),
                      ],
                    )
                  else if (isCurrentIndex)
                    Image.asset(
                      Assets.livingStatic,
                      color: primary,
                      height: 12,
                      cacheHeight: 12.cacheSize(context),
                      semanticLabel: "正在播放：",
                    ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: theme.textTheme.bodyMedium!.fontSize,
                              height: 1.42,
                              letterSpacing: 0.3,
                              fontWeight: isCurrentIndex
                                  ? FontWeight.bold
                                  : null,
                              color: isCurrentIndex ? primary : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pubdate != null)
                          Text(
                            DateFormatUtils.format(pubdate),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              color: theme.colorScheme.outline,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        if (view != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            spacing: 8,
                            children: [
                              StatWidget(
                                value: view,
                                type: StatType.play,
                              ),
                              if (danmaku != null)
                                StatWidget(
                                  value: danmaku,
                                  type: StatType.danmaku,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFav(bool isFav) async {
    final res = await FavHttp.seasonFav(
      isFav: isFav,
      seasonId: widget.seasonId,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      SmartDialog.showToast('${isFav ? '取消' : ''}订阅成功');
      _favState!.value = Success(!isFav);
      widget.ugcIntroController?.seasonFavState[widget.seasonId] = !isFav;
    } else {
      res.toast();
    }
  }

  void _animToTopOrBottom({bool top = true}) {
    final tabIndex = _currentTabIndex.value;
    _itemScrollController[tabIndex].animTo(
      top ^ _isReversed[tabIndex]
          ? 0
          : _calcItemOffset(_getCurrEpisodes.length),
      duration: const Duration(milliseconds: 200),
    );
  }

  Future<void> _animToCurrent() async {
    final currentTabIndex = _currentTabIndex.value;
    if (currentTabIndex != widget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex);
      await Future.pause(const Duration(milliseconds: 225));
    }
    if (!mounted) return;
    _itemScrollController[widget.initialTabIndex].animTo(
      _calcItemOffset(_currentItemIndex),
      duration: const Duration(milliseconds: 200),
    );
  }

  /// The panel's actions, in words, in a menu out of one button: a row of
  /// bare icons that acted at a tap said too little of what each did.
  List<PopupMenuEntry<_PanelAction>> _menuEntries() {
    final tabIndex = _currentTabIndex.value;
    return [
      menuRow('跳到顶部', value: _PanelAction.top),
      menuRow('跳到底部', value: _PanelAction.bottom),
      menuRow('跳到当前播放', value: _PanelAction.current),
      const PopupMenuDivider(),
      if (widget.isSupportReverse == true && tabIndex == widget.initialTabIndex)
        _checkRow(
          '倒序播放',
          checked: widget.isReversed == true,
          value: _PanelAction.reversePlay,
        ),
      _checkRow(
        '倒序显示',
        checked: _isReversed[tabIndex],
        value: _PanelAction.reverseList,
      ),
      if (_favState?.value case Success(:final response)) ...[
        const PopupMenuDivider(),
        menuRow(
          response ? '取消订阅合集' : '订阅合集',
          value: _PanelAction.fav,
        ),
      ],
    ];
  }

  /// A setting that is on or off, the check at the row's end saying it is on.
  PopupMenuItem<_PanelAction> _checkRow(
    String name, {
    required bool checked,
    required _PanelAction value,
  }) => PopupMenuItem(
    value: value,
    child: Semantics(
      checked: checked,
      child: Row(
        children: [
          Expanded(child: Text(name, maxLines: 1, overflow: .ellipsis)),
          if (checked) ...[
            const SizedBox(width: 12),
            const Icon(Icons.check, size: 20),
          ],
        ],
      ),
    ),
  );

  // Picked once the menu has gone, so that onReverse, which closes the sheet
  // first, closes the sheet and not the menu.
  void _onMenuSelected(_PanelAction action) {
    switch (action) {
      case _PanelAction.top:
        _animToTopOrBottom();
      case _PanelAction.bottom:
        _animToTopOrBottom(top: false);
      case _PanelAction.current:
        _animToCurrent();
      case _PanelAction.reversePlay:
        widget.onReverse?.call();
      case _PanelAction.reverseList:
        setState(() {
          final tabIndex = _currentTabIndex.value;
          _isReversed[tabIndex] = !_isReversed[tabIndex];
        });
      case _PanelAction.fav:
        if (_favState?.value case Success(:final response)) {
          _toggleFav(response);
        }
    }
  }

  Widget _buildMenuButton() => PopupMenuButton<_PanelAction>(
    tooltip: '更多',
    icon: const Icon(Icons.more_vert, size: 22),
    itemBuilder: (_) => _menuEntries(),
    onSelected: _onMenuSelected,
  );

  Widget _buildToolbar(ThemeData theme) => Container(
    height: 45,
    padding: EdgeInsets.symmetric(horizontal: showTitle ? 14 : 6),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
    ),
    child: Row(
      children: [
        if (showTitle)
          Text(
            widget.type.title,
            style: theme.textTheme.titleMedium,
          ),
        const Spacer(),
        SizedBox.square(
          dimension: 36,
          child: PopupMenuButton<_PanelAction>(
            tooltip: '更多',
            padding: .zero,
            icon: const Icon(Icons.more_vert, size: 22),
            itemBuilder: (_) => _menuEntries(),
            onSelected: _onMenuSelected,
          ),
        ),
        if (widget.onClose != null)
          iconButton(
            iconSize: 22,
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
      ],
    ),
  );

  /// The title, the menu and the way to close as a bar of glass floating over
  /// the list, which scrolls under it, the sections' tabs a pill below them.
  GlassAppBar _buildGlassBar() => GlassAppBar(
    automaticallyImplyLeading: false,
    centerTitle: false,
    title: Text(widget.type.title),
    actions: [
      _buildMenuButton(),
      if (widget.onClose != null)
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close, size: 22),
          onPressed: widget.onClose,
        ),
    ],
    tabs: _isMulti
        ? LiquidGlassTabBar(
            controller: _tabController,
            labels: [for (final item in widget.list) item.title as String],
          )
        : null,
  );
}

enum _PanelAction { top, bottom, current, reversePlay, reverseList, fav }
