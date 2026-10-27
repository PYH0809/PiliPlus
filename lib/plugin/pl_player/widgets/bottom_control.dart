import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class BottomControl extends StatelessWidget {
  const BottomControl({
    super.key,
    required this.maxWidth,
    required this.isFullScreen,
    required this.controller,
    required this.buildBottomControl,
    required this.videoDetailController,
  });

  final double maxWidth;
  final bool isFullScreen;
  final PlPlayerController controller;
  final ValueGetter<Widget> buildBottomControl;
  final VideoDetailController videoDetailController;

  void onDragStart(ThumbDragDetails duration) {
    feedBack();
    controller.onSeekStart(duration.seconds);
  }

  void onDragUpdate(ThumbDragDetails duration) {
    if (!controller.isFileSource && controller.showSeekPreview) {
      controller.updatePreviewIndex(duration.seconds);
    }
    controller.seekPosition.value = duration.seconds;
  }

  void onSeek(int milliseconds) {
    controller
      ..position.value = milliseconds ~/ 1000
      ..onSeekEnd()
      ..seekTo(Duration(milliseconds: milliseconds), isSeek: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final bufferedBarColor = primary.withValues(alpha: 0.4);

    final glass = GlassSurfaces.installed;
    final progress = Obx(
      () {
        final bar = Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Obx(
              () => ProgressBar(
                progress: controller.progress,
                buffered: controller.buffered.value,
                total: controller.duration.value,
                progressBarColor: primary,
                baseBarColor: const Color(0x33FFFFFF),
                bufferedBarColor: bufferedBarColor,
                thumbColor: primary,
                thumbGlowColor: thumbGlowColor,
                barHeight: 3.5,
                thumbRadius: 7,
                thumbGlowRadius: 25,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onSeek: onSeek,
              ),
            ),
            if (controller.enableBlock &&
                videoDetailController.segmentProgressList.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 5.25,
                child: SegmentProgressBar(
                  segments: videoDetailController.segmentProgressList,
                ),
              ),
            if (controller.showViewPoints &&
                videoDetailController.viewPointList.isNotEmpty &&
                videoDetailController.showVP.value)
              Padding(
                padding: const .only(bottom: 8.75),
                child: ViewPointSegmentProgressBar(
                  segments: videoDetailController.viewPointList,
                  onSeek: PlatformUtils.isDesktop
                      ? (position) => controller.seekTo(position, isSeek: false)
                      : null,
                ),
              ),
            if (videoDetailController.showDmTrendChart.value)
              if (videoDetailController.dmTrend.value?.dataOrNull
                  case final list?)
                buildDmChart(primary, list, videoDetailController, 4.5),
          ],
        );
        final visible = controller.showControls.value;
        // On glass the bar keeps its room while hidden, lest the pane jump.
        return glass
            ? Visibility(
                visible: visible,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: bar,
              )
            : Offstage(offstage: !visible, child: bar);
      },
    );

    if (glass) {
      return _onGlass(context, progress);
    }
    return Padding(
      padding: const .symmetric(horizontal: 10, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
            child: progress,
          ),
          buildBottomControl(),
        ],
      ),
    );
  }

  // One rounded pane: the times flank the progress bar, the buttons below.
  Widget _onGlass(BuildContext context, Widget progress) {
    const timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    Widget time(RxInt seconds) => Obx(
      () => Text(
        DurationUtils.formatDuration(seconds.value),
        style: timeStyle,
      ),
    );
    return Padding(
      padding: isFullScreen
          ? VideoGlass.fullScreenBarPadding(context)
          : const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: VideoGlass(
        radius: isFullScreen ? 26 : 20,
        child: Theme(
          data: VideoGlass.controlsTheme(Theme.of(context)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      time(controller.position),
                      const SizedBox(width: 10),
                      Expanded(child: progress),
                      const SizedBox(width: 10),
                      time(controller.duration),
                    ],
                  ),
                ),
                buildBottomControl(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
