import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/pages/search/controller.dart';
import 'package:PiliPlus/pages/search/widgets/search_glass_header.dart';
import 'package:PiliPlus/pages/search_panel/all/view.dart';
import 'package:PiliPlus/pages/search_panel/article/view.dart';
import 'package:PiliPlus/pages/search_panel/live/view.dart';
import 'package:PiliPlus/pages/search_panel/pgc/view.dart';
import 'package:PiliPlus/pages/search_panel/user/view.dart';
import 'package:PiliPlus/pages/search_panel/video/view.dart';
import 'package:PiliPlus/pages/search_result/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage>
    with SingleTickerProviderStateMixin {
  late SearchResultController _searchResultController;
  late TabController _tabController;
  final String _tag = DateTime.now().millisecondsSinceEpoch.toString();
  final bool _isFromSearch = Get.arguments?['fromSearch'] ?? false;
  SSearchController? sSearchController;
  // The keyword and the tabs on glass, over the results, which scroll under
  // them.
  final bool _glass = GlassSurfaces.installed;

  // The tabs' row below the bar: 2 above the pill, 40 for it, 4 below.
  static const _glassTabsExtent = 2.0 + 40.0 + 4.0;

  @override
  void initState() {
    super.initState();
    _searchResultController = Get.put(
      SearchResultController(),
      tag: _tag,
    );

    _tabController = TabController(
      vsync: this,
      initialIndex: Get.arguments?['initIndex'] ?? 0,
      length: SearchType.actives.length,
    );

    if (_isFromSearch) {
      try {
        sSearchController = Get.find<SSearchController>(
          tag: Get.parameters['tag'],
        );
        _tabController.addListener(listener);
      } catch (_) {}
    }
  }

  void listener() {
    sSearchController?.initIndex = _tabController.index;
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(listener)
      ..dispose();
    super.dispose();
  }

  void _onKeywordTap() {
    if (_isFromSearch) {
      Get.back(result: true);
    } else {
      Get.offNamed(
        '/search',
        parameters: {'text': _searchResultController.keyword},
      );
    }
  }

  String _tabLabel(SearchType item) {
    final count = _searchResultController.count[item.index];
    return '${item.label}${count != -1 ? ' ${count > 99 ? '99+' : count}' : ''}';
  }

  void _onTabTap(int index) {
    if (!_tabController.indexIsChanging) {
      if (_searchResultController.toTopIndex.value == index) {
        _searchResultController.toTopIndex.refresh();
      } else {
        _searchResultController.toTopIndex.value = index;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_glass) {
      return _buildGlass(theme);
    }
    return SimpleScaffold(
      appBar: AppBar(
        shape: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        title: GestureDetector(
          onTap: _onKeywordTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: double.infinity,
            child: Text(
              _searchResultController.keyword,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
            ),
          ),
        ),
      ),
      body: ViewSafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TabBar(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
              controller: _tabController,
              tabs: SearchType.actives
                  .map((item) => Obx(() => Tab(text: _tabLabel(item))))
                  .toList(),
              isScrollable: true,
              indicatorWeight: 0,
              indicatorPadding: const EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 8,
              ),
              indicator: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: const BorderRadius.all(Radius.circular(20)),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: theme.colorScheme.onSecondaryContainer,
              labelStyle:
                  TabBarTheme.of(
                    context,
                  ).labelStyle?.copyWith(fontSize: 13) ??
                  const TextStyle(fontSize: 13),
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              unselectedLabelColor: theme.colorScheme.outline,
              tabAlignment: TabAlignment.start,
              onTap: _onTabTap,
            ),
            Expanded(child: _buildPages()),
          ],
        ),
      ),
    );
  }

  /// The keyword on a capsule of glass, which goes back to search it, and
  /// the tabs on a pill below it, laid over the results.
  Widget _buildGlass(ThemeData theme) {
    return SearchGlassScaffold(
      extent: SearchGlassBar.extent + _glassTabsExtent,
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchGlassBar(
            onFieldTap: _onKeywordTap,
            field: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _searchResultController.keyword,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
            child: Obx(
              () => LiquidGlassTabBar(
                controller: _tabController,
                labels: SearchType.actives.map(_tabLabel).toList(),
                onTap: _onTabTap,
                labelStyle:
                    TabBarTheme.of(context).labelStyle?.copyWith(
                      fontSize: 13,
                    ) ??
                    const TextStyle(fontSize: 13),
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      content: ViewSafeArea(child: _buildPages()),
    );
  }

  Widget _buildPages() {
    return tabBarView(
      controller: _tabController,
      children: SearchType.actives
          .map(
            (item) => switch (item) {
              .all => SearchAllPanel(
                tag: _tag,
                searchType: item,
                keyword: _searchResultController.keyword,
              ),
              .video => SearchVideoPanel(
                tag: _tag,
                searchType: item,
                keyword: _searchResultController.keyword,
              ),
              .media_bangumi || .media_ft => SearchPgcPanel(
                tag: _tag,
                searchType: item,
                keyword: _searchResultController.keyword,
              ),
              .live_room => SearchLivePanel(
                tag: _tag,
                searchType: item,
                keyword: _searchResultController.keyword,
              ),
              .bili_user => SearchUserPanel(
                tag: _tag,
                searchType: item,
                keyword: _searchResultController.keyword,
              ),
              .article => SearchArticlePanel(
                tag: _tag,
                searchType: item,
                keyword: _searchResultController.keyword,
              ),
            },
          )
          .toList(),
    );
  }
}
