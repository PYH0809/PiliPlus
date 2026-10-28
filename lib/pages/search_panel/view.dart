import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search_panel/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract class CommonSearchPanel extends StatefulWidget {
  const CommonSearchPanel({
    super.key,
    required this.keyword,
    required this.searchType,
    required this.tag,
  });

  final String keyword;
  final SearchType searchType;
  final String tag;
}

abstract class CommonSearchPanelState<
  S extends CommonSearchPanel,
  R extends SearchNumData<T>,
  T
>
    extends State<S>
    with AutomaticKeepAliveClientMixin {
  SearchPanelController<R, T> get controller;

  late ColorScheme colorScheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = ColorScheme.of(context);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    controller.cancelListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final header = buildHeader();
    return refreshIndicator(
      onRefresh: controller.onRefresh,
      child: CustomScrollView(
        controller: controller.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Under a header laid over them, as on glass, the results start
          // below it, and their filters scroll away with them, as floating
          // back they would slide under it.
          if (HeaderOverlayInset.of(context) > 0) ...[
            HeaderOverlayInset.sliver(context),
            if (header case SliverFloatingHeaderWidget(:final child))
              SliverToBoxAdapter(child: child)
            else
              ?header,
          ] else
            ?header,
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
            ),
            sliver: Obx(() => _buildBody(controller.loadingState.value)),
          ),
        ],
      ),
    );
  }

  Widget get buildLoading;

  Widget _buildBody(LoadingState<List<T>?> loadingState) {
    return switch (loadingState) {
      Loading() => buildLoading,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? buildList(response)
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget? buildHeader() => null;

  Widget buildList(List<T> list);
}
