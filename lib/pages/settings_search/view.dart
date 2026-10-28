import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_page_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/pages/search/controller.dart' show DebounceStreamState;
import 'package:PiliPlus/pages/setting/models/dm_settings.dart';
import 'package:PiliPlus/pages/setting/models/dyn_settings.dart';
import 'package:PiliPlus/pages/setting/models/extra_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/models/privacy_settings.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/reply_settings.dart';
import 'package:PiliPlus/pages/setting/models/style_settings.dart';
import 'package:PiliPlus/pages/setting/models/video_settings.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState
    extends DebounceStreamState<SettingsSearchPage, String> {
  final _textEditingController = TextEditingController();
  final _focusNode = FocusNode();

  // Whether the field takes focus once the page has grown out of 设置's glass
  // search, rather than as it opens, its keyboard rising with it.
  bool? _focusLater;
  final RxList<SettingsModel> _list = <SettingsModel>[].obs;
  late final _settings = [
    ...extraSettings,
    ...dmSettings,
    ...replySettings,
    ...dynSettings,
    ...privacySettings,
    ...recommendSettings,
    ...videoSettings,
    ...playSettings,
    ...styleSettings,
  ];

  @override
  void onValueChanged(String value) {
    if (value.isEmpty) {
      _list.clear();
    } else {
      value = value.toLowerCase();
      _list.value = _settings
          .where(
            (item) =>
                item.effectiveTitle.toLowerCase().contains(value) ||
                item.effectiveSubtitle?.toLowerCase().contains(value) == true,
          )
          .toList();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focusLater ??= GlassMorphButton.deferUntilOpened(
      context,
      _focusNode.requestFocus,
    );
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _textEditingController.clear();
    _list.clear();
    // In place of a search still waiting out its debounce, which would
    // bring its results back under the empty field.
    ctr?.add('');
  }

  // On glass, the field on a capsule where 设置's search stood, which this
  // page grew out of: the back button beside it, the clear button inside.
  Widget _glassField() {
    final colorScheme = ColorScheme.of(context);
    return SizedBox(
      height: GlassAppBar.buttonSize,
      child: LiquidGlass(
        style: LiquidGlassStyle.regular(colorScheme),
        shadows: floatingGlassShadows(colorScheme),
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
              child: TextField(
                autofocus: !_focusLater!,
                focusNode: _focusNode,
                controller: _textEditingController,
                textAlignVertical: TextAlignVertical.center,
                onChanged: ctr!.add,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索设置',
                  visualDensity: .standard,
                  border: InputBorder.none,
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _textEditingController,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox(width: 14)
                  : IconButton(
                      tooltip: '清除',
                      onPressed: _clear,
                      style: IconButton.styleFrom(
                        splashFactory: NoSplash.splashFactory,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(
                        Icons.cancel,
                        size: 18,
                        color: colorScheme.outline,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: GlassAppBar.enabled
          ? GlassAppBar(expandTitle: true, title: _glassField())
          : AppBar(
              actions: [
                IconButton(
                  onPressed: () {
                    if (_textEditingController.text.isNotEmpty) {
                      _textEditingController.clear();
                      _list.clear();
                    } else {
                      Get.back();
                    }
                  },
                  icon: const Icon(Icons.clear),
                ),
                const SizedBox(width: 10),
              ],
              title: TextField(
                autofocus: true,
                controller: _textEditingController,
                textAlignVertical: TextAlignVertical.center,
                onChanged: ctr!.add,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索',
                  visualDensity: .standard,
                  border: InputBorder.none,
                ),
              ),
            ),
      body: ViewInsetsSafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverHeaderOverlaySpace(),
            ViewSliverSafeArea(
              sliver: Obx(
                () => _list.isEmpty
                    ? const HttpError()
                    : SliverMasonryGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _list[index].widget,
                          childCount: _list.length,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final gridDelegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
  );
}
