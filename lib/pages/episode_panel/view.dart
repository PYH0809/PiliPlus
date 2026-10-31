import 'dart:async' show StreamSubscription;

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
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/menu_entries.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarScrollPhysics;
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_detail/section.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:collection/collection.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class EpisodePanel extends CommonSlidePage {
  const EpisodePanel({
    super.key,
    super.enableSlide,
    this.onReverse,
    required this.type,
    required this.isSidePanel,
    required this.introController,
  });

  final EpisodeType type;
  final bool isSidePanel;
  final VoidCallback? onReverse;
  final CommonIntroController introController;

  @override
  State<EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<EpisodePanel>
    with TickerProviderStateMixin, CommonSlideMixin {
  ColorScheme get colorScheme => theme.colorScheme;
  late final _type = widget.type;
  late final _isSidePanel = widget.isSidePanel;
  late final _introController = widget.introController;

  // ugc
  late final bool _isUgc;
  TabController? _tabController;
  late List<SectionItem> _sections;
  late VideoDetailData _videoDetail;
  late final _ugcController = _introController as UgcIntroController;

  // pgc
  late PgcInfoModel _pgcItem;
  late final _pgcController = _introController as PgcIntroController;

  // fav
  /// The season shown, which the subscription is for. Playing all on into
  /// another season, the page builds the side panel anew, keyed by it.
  late final int? _seasonId;

  // Played on into another season: the panel is about to go, and its tabs
  // and subscription are for the season it showed.
  bool get _seasonGone =>
      _type == .season &&
      _ugcController.videoDetail.rawValue.ugcSeason?.id != _seasonId;
  RxnBool? _favState;

  // reverse
  late final _rxTabIndex = Rx(_tabIndex());
  late final List<bool> _isReversed;
  void _tabListener() {
    _rxTabIndex.value = _tabController!.index;
  }

  late int _lastTabIndex;
  late int _lastItemIndex;
  late final int Function() _tabIndex;
  late final int Function() _itemIndex;
  late List<ugc.BaseEpisodeItem> _episodes;

  ScrollController? _scrollController;

  // Each tab's list's own position, as it registers itself: an index into the
  // primary controller's positions counted the old lists too where the panel
  // was built anew before they had gone, as for another season.
  final Map<int, ScrollPosition> _positions = {};

  void _addUgcListener() {
    _ugcController.indexNotifier.addListener(_refresh);
  }

  void _removeUgcListener() {
    _ugcController.indexNotifier.removeListener(_refresh);
  }

  void _refresh([_]) {
    if (!mounted || _seasonGone) return;
    final tabIndexChanged = _syncTab(_tabIndex(), syncEpisodes: true);
    setState(() {});
    _jumpToCurrIfNeeded(tabIndexChanged);
  }

  bool _syncTab(int tabIndex, {required bool syncEpisodes}) {
    var tabIndexChanged = _lastTabIndex != tabIndex;
    if (syncEpisodes) {
      switch (_type) {
        case .part:
          _videoDetail = _ugcController.videoDetail.rawValue;
          _episodes = _videoDetail.pages!;
        case .season:
          _videoDetail = _ugcController.videoDetail.rawValue;
          _sections = _videoDetail.ugcSeason!.sections!;
          _episodes = _sections[tabIndex].episodes!;
        case .pgc:
          tabIndexChanged = _lastTabIndex != _pgcController.seasonIndex;
          _pgcItem = _pgcController.pgcItem;
          _episodes = _pgcItem.episodes ?? const [];
      }
    }
    _lastTabIndex = tabIndex;
    return tabIndexChanged;
  }

  void _jumpToCurrIfNeeded(bool tabIndexChanged) {
    final itemIndex = _itemIndex();
    if (tabIndexChanged || _lastItemIndex != itemIndex) {
      _jumpToCurrent();
      _lastItemIndex = itemIndex;
    }
  }

  StreamSubscription? _pgcListener;

  void _addPgcListener() {
    _pgcListener = _pgcController.cid.listen(_onCidChanged);
  }

  void _removePgcListener() {
    _pgcListener?.cancel();
    _pgcListener = null;
  }

  void _onCidChanged([_]) {
    WidgetsBinding.instance.addPostFrameCallback(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollController = PrimaryScrollController.of(context);
    if (_scrollController != scrollController) {
      _scrollController = scrollController;
      _positions.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    switch (_type) {
      case .part:
        _isUgc = true;
        _isReversed = [false];
        _tabIndex = () => 0;
        _itemIndex = () => _ugcController.partIndex;
        _videoDetail = _ugcController.videoDetail.rawValue;
        _episodes = _videoDetail.pages!;
        _addUgcListener();

      case .season:
        _isUgc = true;
        _tabIndex = () => _ugcController.sectionIndex;
        _itemIndex = () => _ugcController.seasonIndex;
        _videoDetail = _ugcController.videoDetail.rawValue;
        _sections = _videoDetail.ugcSeason!.sections!;
        if (_sections.length > 1) {
          _tabController = TabController(
            vsync: this,
            length: _sections.length,
            initialIndex: _ugcController.sectionIndex,
          )..addListener(_tabListener);
          _episodes = _sections[_tabIndex()].episodes!;
          _isReversed = List.filled(_sections.length, false);
        } else {
          _isReversed = [false];
          _episodes = _sections.first.episodes!;
        }
        _addUgcListener();

        // The season's own id: the video's top-level season_id can be
        // missing where it has a season.
        _seasonId = _videoDetail.ugcSeason!.id;
        if (_seasonId case final seasonId? when Accounts.main.isLogin) {
          final favState = _ugcController.seasonFavState[seasonId];
          if (favState != null) {
            _favState = RxnBool(favState);
          } else {
            _favState = RxnBool(null);
            VideoHttp.videoRelation(bvid: _ugcController.bvid).then(
              (result) {
                if (!mounted) return;
                if (result case Success(:final response)) {
                  final seasonFav = response.seasonFav ?? false;
                  _favState!.value = seasonFav;
                  _ugcController.seasonFavState[seasonId] = seasonFav;
                }
              },
            );
          }
        }

      case .pgc:
        _isUgc = false;
        _isReversed = [false];
        _tabIndex = () => 0;
        _itemIndex = () => _pgcController.episodeIndex;
        _pgcItem = _pgcController.pgcItem;
        // A season can have sections and no episodes: the side panel then
        // lists none, rather than throwing.
        _episodes = _pgcItem.episodes ?? const [];
        _addPgcListener();
    }

    _lastTabIndex = _tabIndex();
    _lastItemIndex = _itemIndex();
    if (_lastItemIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToPos(offset: _calcItemOffset(_lastItemIndex)),
      );
    }
  }

  void _jumpToTop() => _jumpToPos(top: true);

  void _jumpToBottom() => _jumpToPos(top: false);

  Future<void> _jumpToCurrent() async {
    if (_tabController != null) {
      final tabIndex = _tabIndex();
      if (_tabController!.index != tabIndex) {
        _tabController!.animateTo(tabIndex);
        await Future.pause(const Duration(milliseconds: 225));
        if (!mounted) return;
      }
    }
    _jumpToPos(offset: _calcItemOffset(_itemIndex()));
  }

  void _jumpToPos({double? offset, bool? top}) {
    final scrollController = _scrollController;
    if (!scrollController!.hasClients) {
      if (kDebugMode) assert(false);
      return;
    }
    final tabIndex = _tabController?.index ?? 0;
    final position = _positions[tabIndex];
    if (position == null || !position.hasContentDimensions) return;
    offset ??= (top == true) ^ _isReversed[tabIndex] ? 0 : null;
    final target = offset ?? position.maxScrollExtent;
    if (scrollController is ExtendedNestedScrollController) {
      final nested = scrollController.nestedPositions.firstWhereOrNull(
        (e) => identical(e, position),
      );
      if (nested != null) {
        nested.localJumpTo(target);
        return;
      }
    }
    position.jumpTo(target);
  }

  double _calcItemHeight(ugc.BaseEpisodeItem episode) {
    if (episode is ugc.EpisodeItem && episode.pages!.length > 1) {
      return 167; // 110 + 2 + 10 + 45
    }
    return 112;
  }

  double _calcItemOffset(int index) {
    double offset = 0;
    for (var i = 0; i < index; i++) {
      offset += _calcItemHeight(_episodes[i]);
    }
    return offset + 7;
  }

  static const _throttleTag = 'onChangeEpisode';

  @override
  void dispose() {
    _tabController
      ?..removeListener(_tabListener)
      ..dispose();
    _tabController = null;
    _removeListener();
    super.dispose();
  }

  void _removeListener() {
    if (_isUgc) {
      _removeUgcListener();
    } else {
      _removePgcListener();
    }
  }

  bool _popIfNeeded() {
    if (_isSidePanel) return false;
    _pop();
    return true;
  }

  void _pop() {
    _removeListener();
    Get.back();
  }

  // On glass the sheet's bar floats over its list, but not where the panel
  // is glass already, as the full-screen one on the video's VideoGlass,
  // since glass never lies on glass. As GlassFab tells.
  late final bool _floatingBar =
      !_isSidePanel &&
      GlassAppBar.enabled &&
      !GlassSurfaces.onGlass(context) &&
      context.findAncestorWidgetOfExactType<VideoGlass>() == null;

  /// How far the floating bar covers the top of the list.
  double get _barInset =>
      _floatingBar ? _buildGlassBar().preferredSize.height : 0;

  @override
  Widget buildPage() {
    if (_floatingBar) {
      return Material(
        color: colorScheme.surface,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: GlassAppBarBody(
            appBar: _buildGlassBar(),
            body: enableSlide ? slideList() : buildList(),
          ),
        ),
      );
    }
    final child = Column(
      children: [
        _buildToolbar(),
        if (_tabController != null)
          TabBar(
            dividerHeight: 1,
            isScrollable: true,
            controller: _tabController,
            padding: const .only(right: 60),
            tabs: _sections.map((e) => Tab(text: e.title)).toList(),
            dividerColor: colorScheme.outline.withValues(alpha: 0.1),
          ),
        Expanded(child: enableSlide ? slideList() : buildList()),
      ],
    );
    if (!_isSidePanel) {
      return ColoredBox(color: colorScheme.surface, child: child);
    }
    return child;
  }

  @override
  Widget buildList() {
    if (_tabController != null) {
      return TabBarView(
        controller: _tabController,
        physics: tabBarScrollPhysics,
        horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
        children: _sections
            .mapIndexed((i, e) => _buildBody(e.episodes!, tabIndex: i))
            .toList(),
      );
    }
    return _buildBody(_episodes);
  }

  Widget _buildBody(List<ugc.BaseEpisodeItem> episodes, {int tabIndex = 0}) {
    final isCurrTab = tabIndex == _tabIndex();

    Widget child;
    child = SliverVariedExtentList.builder(
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final isCurrItem = isCurrTab && index == _itemIndex();
        Widget episodeItem = _buildEpisodeItem(
          episode: episode,
          tabIndex: tabIndex,
          index: index,
          length: episodes.length,
          isCurrItem: isCurrItem,
        );
        if (episode is ugc.EpisodeItem && episode.pages!.length > 1) {
          return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              episodeItem, // 110
              Padding(
                padding: const .symmetric(horizontal: 12, vertical: 5), // 10
                child: PagePanel(
                  // 45
                  onBack: _isSidePanel ? null : _pop,
                  parts: isCurrItem ? null : episode.pages,
                  cover: episode.arc?.pic,
                  bvid: episode.bvid ?? IdUtils.av2bv(episode.aid!),
                  ugcIntroController: _ugcController,
                ),
              ),
            ],
          );
        }
        return episodeItem;
      },
      itemExtentBuilder: (index, _) => _calcItemHeight(episodes[index]),
    );

    final list = child;
    child = CustomScrollView(
      primary: true,
      reverse: _isReversed[tabIndex],
      key: ValueKey(_scrollController.hashCode),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: 7 + _barInset,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
          ),
          sliver: Builder(
            builder: (context) {
              _positions[tabIndex] = Scrollable.of(context).position;
              return list;
            },
          ),
        ),
      ],
    );

    if (_tabController != null) {
      return KeepAliveWrapper(child: child);
    }
    return child;
  }

  late final _isVip = Accounts.isVideoVip;
  void _onChangeEpisode(
    int tabIndex,
    int index,
    ugc.BaseEpisodeItem episode,
    String title,
  ) {
    if (!_popIfNeeded()) {
      _syncTab(tabIndex, syncEpisodes: false);
      _lastItemIndex = index;
    }

    if (episode.badge == "会员" && !_isVip) {
      SmartDialog.showToast('需要大会员');
      // return;
    }

    if (_isUgc) {
      _ugcController.onChangeEpisode(episode);
    } else {
      _pgcController.onChangeEpisode(episode, episodeType: .episode);
    }
  }

  Widget _buildEpisodeItem({
    required ugc.BaseEpisodeItem episode,
    required int tabIndex,
    required int index,
    required int length,
    required bool isCurrItem,
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
        cover = part.firstFrame ?? _videoDetail.pic;
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
    late final Color primary = colorScheme.primary;

    void onLongPress() {
      if (cover?.isNotEmpty == true) {
        imageSaveDialog(title: title, cover: cover, bvid: bvid);
      }
    }

    return Padding(
      padding: const .only(bottom: 2),
      child: SizedBox(
        height: 110,
        child: Material(
          type: .transparency,
          child: InkWell(
            onTap: () {
              if (isCurrItem) return;
              // At once, a second tap meanwhile let be: put off, the pick
              // could come as the panel closed, and its pop then closed the
              // page under it.
              EasyThrottle.throttle(
                _throttleTag,
                const Duration(milliseconds: 200),
                () => _onChangeEpisode(tabIndex, index, episode, title),
              );
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
                      clipBehavior: .none,
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
                        if (_type == .part)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const .symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: const .only(
                                  bottomLeft: .circular(4),
                                  topRight: Style.imgRadius,
                                ),
                              ),
                              child: Text(
                                (index + 1).toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSecondaryContainer,
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
                            type: episode.badgeType,
                          ),
                      ],
                    )
                  else if (isCurrItem)
                    Image.asset(
                      Assets.livingStatic,
                      color: primary,
                      height: 12,
                      cacheHeight: 12.cacheSize(context),
                    ),
                  Expanded(
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            textAlign: .start,
                            style: TextStyle(
                              height: 1.42,
                              letterSpacing: 0.3,
                              fontWeight: isCurrItem ? .bold : null,
                              color: isCurrItem ? primary : null,
                            ),
                            maxLines: 2,
                            overflow: .ellipsis,
                          ),
                        ),
                        if (pubdate != null)
                          Text(
                            DateFormatUtils.format(pubdate),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              color: colorScheme.outline,
                              overflow: .clip,
                            ),
                          ),
                        if (view != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            spacing: 8,
                            children: [
                              StatWidget(
                                value: view,
                                type: .play,
                              ),
                              if (danmaku != null)
                                StatWidget(
                                  value: danmaku,
                                  type: .danmaku,
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

  Future<void> _onFavSeason(bool isFav) async {
    final res = await FavHttp.seasonFav(
      isFav: isFav,
      seasonId: _seasonId!,
    );
    if (res.isSuccess) {
      _favState!.toggle();
      _ugcController.seasonFavState[_seasonId] = !isFav;
      SmartDialog.showToast('${isFav ? '取消' : ''}订阅成功');
    } else {
      res.toast();
    }
  }

  /// Whether the list plays from its end: shown, and picked, only on the tab
  /// that plays.
  bool get _isDataReversed => switch (_type) {
    .part => _videoDetail.isPageReversed,
    .season => _sections[_rxTabIndex.value].isReversed,
    .pgc => false,
  };

  /// The panel's actions, in words, in a menu out of one button: a row of
  /// bare icons that acted at a tap said too little of what each did.
  List<PopupMenuEntry<_PanelAction>> _menuEntries() {
    final tabIndex = _rxTabIndex.value;
    return [
      menuRow('跳到顶部', value: _PanelAction.top),
      menuRow('跳到底部', value: _PanelAction.bottom),
      menuRow('跳到当前播放', value: _PanelAction.current),
      const PopupMenuDivider(),
      if (_isUgc && tabIndex == _tabIndex())
        _checkRow(
          '倒序播放',
          checked: _isDataReversed,
          value: _PanelAction.reversePlay,
        ),
      _checkRow(
        '倒序显示',
        checked: _isReversed[tabIndex],
        value: _PanelAction.reverseList,
      ),
      if (_favState?.value case final isFav?) ...[
        const PopupMenuDivider(),
        menuRow(isFav ? '取消订阅合集' : '订阅合集', value: _PanelAction.fav),
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

  // Picked once the menu has gone, so that closing the sheet before reversing
  // closes the sheet and not the menu.
  void _onMenuSelected(_PanelAction action) {
    switch (action) {
      case _PanelAction.top:
        _jumpToTop();
      case _PanelAction.bottom:
        _jumpToBottom();
      case _PanelAction.current:
        _jumpToCurrent();
      case _PanelAction.reversePlay:
        _popIfNeeded();
        widget.onReverse!();
      case _PanelAction.reverseList:
        setState(() {
          final tabIndex = _rxTabIndex.value;
          _isReversed[tabIndex] = !_isReversed[tabIndex];
        });
      case _PanelAction.fav:
        if (_favState?.value case final isFav?) _onFavSeason(isFav);
    }
  }

  Widget _buildMenuButton() => PopupMenuButton<_PanelAction>(
    tooltip: '更多',
    icon: const Icon(Icons.more_vert, size: 22),
    itemBuilder: (_) => _menuEntries(),
    onSelected: _onMenuSelected,
  );

  Widget _buildToolbar() => Container(
    height: 45,
    padding: .symmetric(horizontal: !_isSidePanel ? 14 : 6),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
    ),
    child: Row(
      children: [
        if (!_isSidePanel)
          Text(
            _type.title,
            style: const TextStyle(fontSize: 16),
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
        if (!_isSidePanel)
          iconButton(
            iconSize: 22,
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: Get.back,
          ),
      ],
    ),
  );

  /// The title, the menu and the way to close as a bar of glass floating over
  /// the list, which scrolls under it, the sections' tabs a pill below them.
  GlassAppBar _buildGlassBar() => GlassAppBar(
    automaticallyImplyLeading: false,
    centerTitle: false,
    title: Text(_type.title),
    actions: [
      _buildMenuButton(),
      IconButton(
        tooltip: '关闭',
        icon: const Icon(Icons.close, size: 22),
        onPressed: Get.back,
      ),
    ],
    tabs: _tabController != null
        ? LiquidGlassTabBar(
            controller: _tabController!,
            labels: [for (final section in _sections) section.title ?? ''],
          )
        : null,
  );
}

enum _PanelAction { top, bottom, current, reversePlay, reverseList, fav }
