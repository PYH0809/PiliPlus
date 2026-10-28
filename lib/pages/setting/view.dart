import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/about/view.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class _SettingsModel {
  final SettingType type;
  final String? subtitle;
  final Icon icon;

  const _SettingsModel({
    required this.type,
    this.subtitle,
    required this.icon,
  });
}

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late SettingType _type = .privacySetting;
  final RxBool _noAccount = Accounts.account.isEmpty.obs;
  late bool _isPortrait;
  late ThemeData theme;

  static const List<_SettingsModel> _items = [
    _SettingsModel(
      type: .privacySetting,
      subtitle: '账号、黑名单',
      icon: Icon(Icons.privacy_tip_outlined),
    ),
    _SettingsModel(
      type: .recommendSetting,
      subtitle: '推荐来源（web/app）、刷新保留内容、过滤器',
      icon: Icon(Icons.explore_outlined),
    ),
    _SettingsModel(
      type: .videoSetting,
      subtitle: '画质、音质、解码、缓冲、音频输出等',
      icon: Icon(Icons.video_settings_outlined),
    ),
    _SettingsModel(
      type: .playSetting,
      subtitle: '双击/长按、全屏、后台播放、弹幕、字幕、底部进度条等',
      icon: Icon(Icons.touch_app_outlined),
    ),
    _SettingsModel(
      type: .dmSetting,
      subtitle: '点击弹幕、弹幕行高、彩色弹幕、合并弹幕',
      icon: Icon(CustomIcons.dm_settings),
    ),
    _SettingsModel(
      type: .replySetting,
      subtitle: '过滤、屏蔽、记录、默认展示等',
      icon: Icon(Icons.comment_outlined),
    ),
    _SettingsModel(
      type: .dynSetting,
      subtitle: '过滤、屏蔽、默认展示等',
      icon: Icon(CustomIcons.motion_photos_on_outlined),
    ),
    _SettingsModel(
      type: .styleSetting,
      subtitle: '横屏适配（平板）、侧栏、列宽、首页、动态红点、主题、字号、图片、帧率等',
      icon: Icon(Icons.style_outlined),
    ),
    _SettingsModel(
      type: .extraSetting,
      subtitle: '震动、搜索、收藏、ai、评论、动态、代理、更新检查等',
      icon: Icon(Icons.extension_outlined),
    ),
    _SettingsModel(
      type: .webdavSetting,
      icon: Icon(MdiIcons.databaseCogOutline),
    ),
    _SettingsModel(
      type: .about,
      icon: Icon(Icons.info_outline),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    theme = Theme.of(context);
    _isPortrait = MediaQuery.sizeOf(context).isPortrait;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPortrait && GlassAppBar.enabled) {
      return _buildGlassPanes();
    }
    final glass = GlassAppBar.enabled;
    return SimpleScaffold(
      appBar: GlassAppBar(
        expandTitle: glass,
        title: glass
            ? _glassSearch()
            : _isPortrait
            ? const Text('设置')
            : Text(_type.title),
      ),
      body: ViewSafeArea(
        child: _isPortrait
            ? _buildList(theme)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildList(theme),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                  Expanded(
                    flex: 6,
                    child: _detail,
                  ),
                ],
              ),
      ),
    );
  }

  Widget get _detail => switch (_type) {
    .webdavSetting => const WebDavSettingPage(showAppBar: false),
    .about => const AboutPage(showAppBar: false),
    _ => CommonSetting(settingType: _type, showAppBar: false),
  };

  // On glass each pane has a bar of its own, as iPad's split views have, so
  // that each title stands over its own pane and the divider runs between
  // the bars rather than through one.
  Widget _buildGlassPanes() {
    return Material(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: MediaQuery.removePadding(
              context: context,
              removeRight: true,
              child: SimpleScaffold(
                appBar: GlassAppBar(expandTitle: true, title: _glassSearch()),
                body: ViewSafeArea(child: _buildList(theme)),
              ),
            ),
          ),
          VerticalDivider(
            width: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
          Expanded(
            flex: 6,
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: SimpleScaffold(
                appBar: GlassAppBar(
                  automaticallyImplyLeading: false,
                  title: Text(_type.title),
                ),
                body: ViewSafeArea(child: _detail),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _noAccount.close();
    super.dispose();
  }

  void _toPage(SettingType type) {
    if (_isPortrait) {
      Get.to(
        () => switch (type) {
          .webdavSetting => const WebDavSettingPage(),
          .about => const AboutPage(),
          _ => CommonSetting(settingType: type),
        },
      );
    } else {
      _type = type;
      setState(() {});
    }
  }

  Color? _getTileColor(ThemeData theme, SettingType type) {
    if (_isPortrait) {
      return null;
    } else {
      return type == _type ? theme.colorScheme.onInverseSurface : null;
    }
  }

  Widget _buildList(ThemeData theme) {
    final padding = MediaQuery.viewPaddingOf(context);
    TextStyle titleStyle = theme.textTheme.titleMedium!;
    TextStyle subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    return ListView(
      padding: EdgeInsets.only(bottom: padding.bottom + 100),
      children: [
        const HeaderOverlaySpace(),
        if (!GlassAppBar.enabled) _buildSearchItem(theme),
        ..._items
            .take(_items.length - 1)
            .map(
              (item) => ListTile(
                tileColor: _getTileColor(theme, item.type),
                onTap: () => _toPage(item.type),
                leading: item.icon,
                title: Text(item.type.title, style: titleStyle),
                subtitle: item.subtitle == null
                    ? null
                    : Text(item.subtitle!, style: subTitleStyle),
              ),
            ),
        ListTile(
          onTap: () => LoginPageController.switchAccountDialog(context),
          leading: const Icon(Icons.switch_account_outlined),
          title: Text('切换账号', style: titleStyle),
        ),
        Obx(
          () => _noAccount.value
              ? const SizedBox.shrink()
              : ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  onTap: () => _logoutDialog(context),
                  title: Text('退出登录', style: titleStyle),
                ),
        ),
        ListTile(
          tileColor: _getTileColor(theme, _items.last.type),
          onTap: () => _toPage(_items.last.type),
          leading: _items.last.icon,
          title: Text(_items.last.type.title, style: titleStyle),
        ),
      ],
    );
  }

  Future<void> _removeAccounts(Set<LoginAccount> accounts) async {
    await Accounts.deleteAll(accounts);
    if (mounted) _noAccount.value = Accounts.account.isEmpty;
  }

  static Future<LoginAccount?> _logoutWrapper(LoginAccount account) async {
    try {
      final res = await LoginHttp.logout(account);
      return res.isSuccess ? account : null;
    } catch (e, s) {
      Utils.reportError(e, s);
      return null;
    }
  }

  Future<void> _logoutDialog(BuildContext context) async {
    final result = await showDialog<Set<LoginAccount>>(
      context: context,
      builder: (context) => MultiSelectDialog<LoginAccount>(
        title: '选择要登出的账号uid',
        initValues: const Iterable.empty(),
        values: {
          for (final i in Accounts.account.values) i: i.mid.toString(),
        },
      ),
    );
    if (!context.mounted || result == null || result.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('提示'),
          content: Text(
            "确认要退出以下账号登录吗\n\n${result.map((i) => i.mid).join('\n')}",
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '点错了',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                _removeAccounts(result);
              },
              child: Text(
                '仅登出',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () async {
                SmartDialog.showLoading();
                final res = await Future.wait(result.map(_logoutWrapper));
                SmartDialog.dismiss();
                final logoutAccounts = res.nonNulls.toSet();
                if (logoutAccounts.isEmpty) {
                  SmartDialog.showToast('所选账号均退出登录失败');
                } else {
                  Get.back();
                  _removeAccounts(logoutAccounts);
                  if (logoutAccounts.length != result.length) {
                    result.removeWhere(logoutAccounts.contains);
                    SmartDialog.showToast(
                      '账号 ${result.map((i) => i.mid).join(",")} 退出登录失败',
                    );
                  }
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  // On glass the search floats in the bar beside the back button, on a pane
  // of its own, and its page grows out of it. Its hint names the page in
  // place of a title: 设置 on its own would only crowd the row.
  Widget _glassSearch() {
    final colorScheme = theme.colorScheme;
    return SizedBox(
      height: GlassAppBar.buttonSize,
      child: GlassMorphButton(
        shadows: floatingGlassShadows(colorScheme),
        onTap: (button) => button.toNamed('/settingsSearch'),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '搜索设置',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchItem(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: 8,
    ),
    child: Material(
      color: theme.colorScheme.onInverseSurface,
      borderRadius: const BorderRadius.all(Radius.circular(50)),
      child: InkWell(
        onTap: () => Get.toNamed('/settingsSearch'),
        borderRadius: const BorderRadius.all(Radius.circular(50)),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  size: 18,
                  applyTextScaling: true,
                  Icons.search,
                ),
                Text(
                  ' 搜索',
                  style: TextStyle(height: 1),
                  strutStyle: StrutStyle(height: 1, leading: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
