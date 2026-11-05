import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/video/related/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class RelatedVideoPanel extends StatefulWidget {
  const RelatedVideoPanel({super.key, required this.heroTag});
  final String heroTag;
  @override
  State<RelatedVideoPanel> createState() => _RelatedVideoPanelState();
}

class _RelatedVideoPanelState extends State<RelatedVideoPanel> with GridMixin {
  late final RelatedController _relatedController;

  // The list the cards are shown for, and how many of them are built: the
  // list arrives as the page opens, and its cards, mostly their titles' text,
  // took a OnePlus 7 Pro 7-15 ms to build and lay out at once, past a
  // 120 Hz frame. They come a couple a frame, over plain boxes their size.
  List<HotVideoItemModel>? _shownList;
  final _shown = ValueNotifier(0);

  /// How many cards come a frame, until [_shownAtOnce] are built.
  static const _perFrame = 2;

  /// From here on the rest come at once: past the screen, a grid builds none
  /// of them yet.
  static const _shownAtOnce = 8;

  // Each frame, a couple more, until all are: only the cards that cross it
  // build, the rest stay as they are.
  void _showMore(List<HotVideoItemModel> list) {
    if (identical(list, _shownList)) {
      return;
    }
    _shownList = list;
    _shown.value = 0;
    void next(Duration _) {
      if (!mounted || !identical(list, _shownList)) {
        return;
      }
      final shown = _shown.value + _perFrame;
      _shown.value = shown >= _shownAtOnce ? list.length : shown;
      if (_shown.value < list.length) {
        SchedulerBinding.instance
          ..addPostFrameCallback(next)
          ..scheduleFrame();
      }
    }

    SchedulerBinding.instance.addPostFrameCallback(next);
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _relatedController = Get.putOrFind(
      RelatedController.new,
      tag: widget.heroTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 7, bottom: 100),
      sliver: Obx(() => _buildBody(_relatedController.loadingState.value)),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? _cards(response)
            : const SliverToBoxAdapter(),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _relatedController.onReload,
      ),
    };
  }

  Widget _cards(List<HotVideoItemModel> response) {
    _showMore(response);
    return SliverGrid.builder(
      // Another video's list comes a couple a frame again: its cards start
      // over, while a card removed from this one leaves the rest as they are.
      key: ObjectKey(response),
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) => _Staged(
        index: index,
        shown: _shown,
        builder: () => VideoCardH(
          videoItem: response[index],
          onRemove: () => _relatedController.loadingState
            ..value.data!.removeAt(index)
            ..refresh(),
        ),
      ),
      itemCount: response.length,
    );
  }
}

/// The card at [index], once [shown] has passed it, and its placeholder till
/// then: it builds again only as it does.
class _Staged extends StatefulWidget {
  const _Staged({
    required this.index,
    required this.shown,
    required this.builder,
  });

  final int index;
  final ValueListenable<int> shown;
  final Widget Function() builder;

  @override
  State<_Staged> createState() => _StagedState();
}

class _StagedState extends State<_Staged> {
  late bool _built = widget.index < widget.shown.value;

  @override
  void initState() {
    super.initState();
    if (!_built) {
      widget.shown.addListener(_handleShown);
    }
  }

  void _handleShown() {
    if (widget.index < widget.shown.value) {
      widget.shown.removeListener(_handleShown);
      setState(() => _built = true);
    }
  }

  @override
  void dispose() {
    widget.shown.removeListener(_handleShown);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _built ? widget.builder() : const _CardPlaceholder();
}

/// Where a card comes a frame or two later: its cover's box, still, as the
/// skeleton's first frame shows it.
class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(horizontal: Style.safeSpace, vertical: 5),
      child: Align(
        alignment: .centerLeft,
        child: AspectRatio(
          aspectRatio: Style.aspectRatio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ColorScheme.of(context).onInverseSurface,
              borderRadius: Style.mdRadius,
            ),
          ),
        ),
      ),
    );
  }
}
