import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  late ColorScheme _colorScheme;
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();

  // The glass header is laid over the content and slides away rather than
  // shrinking it, so the content needs no correction as it hides.
  late final bool _glass = _mainController.liquidGlass;

  @override
  bool get needsCorrection => _homeController.hideTopBar && !_glass;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_glass) {
      return _buildGlass();
    }
    Widget tabBar;
    if (_homeController.tabs.length > 1) {
      tabBar = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 42,
          width: double.infinity,
          child: TabBar(
            controller: _homeController.tabController,
            tabs: _homeController.tabs.map((e) => Tab(text: e.label)).toList(),
            isScrollable: true,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            tabAlignment: TabAlignment.center,
            onTap: _onTabTap,
          ),
        ),
      );
      if (_homeController.hideTopBar &&
          _mainController.barHideType == .instant) {
        tabBar = Material(
          color: _colorScheme.surface,
          child: tabBar,
        );
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    return Column(
      children: [
        if (!_mainController.useSideBar &&
            MediaQuery.sizeOf(context).isPortrait)
          customAppBar(),
        tabBar,
        Expanded(
          child: onBuild(
            tabBarView(
              controller: _homeController.tabController,
              children: _homeController.tabs.map((e) => e.page).toList(),
            ),
          ),
        ),
      ],
    );
  }

  void _onTabTap(int index) {
    feedBack();
    if (!_homeController.tabController.indexIsChanging) {
      _homeController.animateToTop();
    }
  }

  void _toSearch() => Get.toNamed(
    '/search',
    parameters: _homeController.enableSearchWord
        ? {'hintText': _homeController.defaultSearch.value}
        : null,
  );

  /// The header in liquid glass, laid over the content, which scrolls under it
  /// starting below it.
  Widget _buildGlass() {
    final showSearch =
        !_mainController.useSideBar && MediaQuery.sizeOf(context).isPortrait;
    final hasTabs = _homeController.tabs.length > 1;
    const tabsExtent = 6.0 + 40.0 + 4.0;
    final inset =
        (showSearch ? Style.topBarHeight : 0.0) + (hasTabs ? tabsExtent : 6.0);

    Widget header = LiquidGlassHeader(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSearch) _glassSearchRow(),
          if (hasTabs)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              child: LiquidGlassTabBar(
                controller: _homeController.tabController,
                labels: _homeController.tabs.map((e) => e.label).toList(),
                onTap: _onTabTap,
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );

    if (showSearch && _homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        final child = header;
        header = Obx(
          () => Transform.translate(
            offset: Offset(0, -barOffset.value),
            child: child,
          ),
        );
      } else if (_homeController.showTopBar case final showTopBar?) {
        final child = header;
        header = Obx(
          () => TweenAnimationBuilder<double>(
            tween: Tween(end: showTopBar.value ? 0 : -Style.topBarHeight),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubicEmphasized,
            builder: (context, dy, child) =>
                Transform.translate(offset: Offset(0, dy), child: child),
            child: child,
          ),
        );
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: HeaderOverlayInset(
            inset: inset,
            child: onBuild(
              tabBarView(
                controller: _homeController.tabController,
                children: _homeController.tabs.map((e) => e.page).toList(),
              ),
            ),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: header),
      ],
    );
  }

  Widget _glassSearchRow() {
    return SizedBox(
      height: Style.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: LiquidGlassButton(
                  onTap: _toSearch,
                  shadows: floatingGlassShadows(_colorScheme),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(
                        Icons.search_outlined,
                        color: _colorScheme.onSecondaryContainer,
                        semanticLabel: '搜索',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Obx(
                          () => Text(
                            _homeController.defaultSearch.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _colorScheme.outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            msgBadge(_mainController, glass: true),
            userAvatar(
              colorScheme: _colorScheme,
              mainController: _mainController,
            ),
          ],
        ),
      ),
    );
  }

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(),
        const SizedBox(width: 4),
        msgBadge(_mainController),
        const SizedBox(width: 8),
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
      ],
    );
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(
          () {
            final offset = barOffset.value;
            return CustomHeightWidget(
              offset: Offset(0, -offset),
              height: Style.topBarHeight - offset,
              child: Padding(
                padding: padding,
                child: child,
              ),
            );
          },
        );
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(() {
          final showSearchBar = showTopBar.value;
          return AnimatedOpacity(
            opacity: showSearchBar ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              height: showSearchBar ? Style.topBarHeight : 0,
              padding: padding,
              child: child,
            ),
          );
        });
      }
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  Widget searchBar() {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: SizedBox(
        height: 44,
        child: Material(
          borderRadius: borderRadius,
          color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
          child: InkWell(
            borderRadius: borderRadius,
            splashColor: _colorScheme.primaryContainer.withValues(
              alpha: 0.3,
            ),
            onTap: _toSearch,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_outlined,
                  color: _colorScheme.onSecondaryContainer,
                  semanticLabel: '搜索',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Obx(
                    () => Text(
                      _homeController.defaultSearch.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget userAvatar({
  required ColorScheme colorScheme,
  required MainController mainController,
}) {
  return Semantics(
    label: "我的",
    child: Obx(
      () {
        if (mainController.accountService.isLogin.value) {
          return Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                type: .avatar,
                width: 34,
                height: 34,
                src: mainController.accountService.face.value,
              ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: mainController.toMinePage,
                    splashColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    customBorder: const CircleBorder(),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Obx(
                  () => MineController.anonymity.value
                      ? IgnorePointer(
                          child: Container(
                            padding: const .all(2),
                            decoration: BoxDecoration(
                              shape: .circle,
                              color: colorScheme.secondaryContainer,
                            ),
                            child: Icon(
                              size: 14,
                              MdiIcons.incognito,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: '点击登录',
            style: IconButton.styleFrom(
              padding: .zero,
              backgroundColor: colorScheme.onInverseSurface,
            ),
            onPressed: mainController.toMinePage,
            icon: Icon(
              Icons.person_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
          ),
        );
      },
    ),
  );
}

void _openMessages(MainController mainController) {
  mainController
    ..clearUnreadMsg()
    ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
  Get.toNamed('/whisper');
}

Widget msgBadge(MainController mainController, {bool glass = false}) {
  return Obx(
    () {
      if (mainController.accountService.isLogin.value) {
        final count = mainController.msgUnReadCount.value;
        final isNumBadge = mainController.msgBadgeMode == .number;
        final icon = Badge(
          isLabelVisible:
              mainController.msgBadgeMode != .hidden && count != null,
          alignment: isNumBadge
              ? const Alignment(0.0, -0.85)
              : const Alignment(1.0, -0.85),
          label: isNumBadge && count != null ? Text(count) : null,
          child: const Icon(Icons.notifications_none),
        );
        if (glass) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox.square(
              dimension: 40,
              child: LiquidGlassButton(
                tooltip: '消息',
                onTap: () => _openMessages(mainController),
                child: Center(child: icon),
              ),
            ),
          );
        }
        return IconButton(
          tooltip: '消息',
          onPressed: () => _openMessages(mainController),
          icon: icon,
        );
      }
      return const SizedBox.shrink();
    },
  );
}
