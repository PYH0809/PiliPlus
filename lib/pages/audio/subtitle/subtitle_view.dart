import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart' show DetailItem;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_mixin.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// The subtitles in place of the cover: a small cover and the title, which
/// go back to the cover when tapped, the language, then the lines.
class AudioSubtitlePanel extends StatelessWidget {
  const AudioSubtitlePanel({
    super.key,
    required this.controller,
    required this.item,
  });

  final AudioSubtitleMixin controller;
  final DetailItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: .opaque,
                onTap: controller.toggleSubtitle,
                child: Row(
                  spacing: 12,
                  children: [
                    NetworkImgLayer(
                      src: item.arc.cover.http2https,
                      width: 48,
                      height: 48,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: .min,
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            item.arc.title,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: .bold,
                            ),
                          ),
                          if (item.owner.hasName())
                            Text(
                              item.owner.name,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _SubtitleLanguage(controller: controller),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: AudioSubtitleList(controller: controller)),
      ],
    );
  }
}

class _SubtitleLanguage extends StatelessWidget {
  const _SubtitleLanguage({required this.controller});

  final AudioSubtitleMixin controller;

  static String _label(Subtitle subtitle) {
    final lanDoc = subtitle.lanDoc ?? subtitle.lan;
    return subtitle.isAi && !lanDoc.contains('AI') ? '$lanDoc（AI）' : lanDoc;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final subtitles = controller.subtitles;
      final index = controller.subtitleIndex.value;
      if (index < 0 || index >= subtitles.length) {
        return const SizedBox.shrink();
      }
      final colorScheme = ColorScheme.of(context);
      final canChange = subtitles.length > 1;
      final chip = DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: const .all(.circular(14)),
        ),
        child: Padding(
          padding: .fromLTRB(10, 4, canChange ? 4 : 10, 4),
          child: Row(
            mainAxisSize: .min,
            children: [
              Text(
                _label(subtitles[index]),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              if (canChange)
                Icon(
                  MdiIcons.unfoldMoreHorizontal,
                  size: 14,
                  color: colorScheme.onSecondaryContainer,
                ),
            ],
          ),
        ),
      );
      if (!canChange) return chip;
      return PopupMenuButton<int>(
        tooltip: '字幕语言',
        initialValue: index,
        onSelected: controller.selectSubtitle,
        itemBuilder: (_) => List.generate(
          subtitles.length,
          (i) => PopupMenuItem(
            value: i,
            height: 40,
            child: Text(
              _label(subtitles[i]),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        child: chip,
      );
    });
  }
}

/// The lines, scrolled to keep the one being spoken in the middle. A touch
/// stops the scrolling along, and after a drag it waits [_resumeDelay] from
/// the end of the scroll to go on.
class AudioSubtitleList extends StatefulWidget {
  const AudioSubtitleList({super.key, required this.controller});

  final AudioSubtitleMixin controller;

  @override
  State<AudioSubtitleList> createState() => _AudioSubtitleListState();
}

class _AudioSubtitleListState extends State<AudioSubtitleList> {
  static const _resumeDelay = Duration(seconds: 3);

  late final AudioSubtitleMixin _controller = widget.controller;
  final _scrollController = ScrollController();
  final _listController = ListController();
  late final Worker _lineWorker;
  late final Worker _linesWorker;

  /// Whether the list scrolls along with the line being spoken.
  bool _following = true;
  Timer? _resumeTimer;

  /// Fingers on the list.
  int _pointers = 0;

  /// Bumped to stop the scrolling to a line, which jumps on every frame.
  int _animation = 0;

  @override
  void initState() {
    super.initState();
    _lineWorker = ever(_controller.subtitleLine, _onLineChanged);
    _linesWorker = ever(_controller.subtitleLines, (_) => _jumpAfterLayout());
    _jumpAfterLayout();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _lineWorker.dispose();
    _linesWorker.dispose();
    _listController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLineChanged(int index) {
    if (_following && _pointers == 0) {
      _scrollTo(index, animate: true);
    }
  }

  void _jumpAfterLayout() {
    _resumeTimer?.cancel();
    _following = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollTo(_controller.subtitleLine.value, animate: false);
      }
    });
  }

  void _scrollTo(int index, {required bool animate}) {
    if (!_listController.isAttached || !_scrollController.hasClients) return;
    final count = _listController.numberOfItems;
    if (count == 0) return;
    // before the first line, wait with it in the middle
    index = index.clamp(0, count - 1);
    final animation = ++_animation;
    if (animate) {
      _listController.animateToItem(
        index: () => animation == _animation ? index : null,
        scrollController: _scrollController,
        alignment: 0.5,
        duration: (_) => const Duration(milliseconds: 500),
        curve: (_) => Curves.easeOutCubic,
      );
    } else {
      _listController.jumpToItem(
        index: index,
        scrollController: _scrollController,
        alignment: 0.5,
      );
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    switch (notification) {
      case UserScrollNotification(:final direction) when direction != .idle:
        _following = false;
        _resumeTimer?.cancel();
      case ScrollEndNotification() when !_following:
        _resumeTimer?.cancel();
        _resumeTimer = Timer(_resumeDelay, _resume);
    }
    return false;
  }

  void _resume() {
    if (_pointers > 0) {
      _resumeTimer = Timer(_resumeDelay, _resume);
      return;
    }
    _following = true;
    _scrollTo(_controller.subtitleLine.value, animate: true);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers++;
    // or its jumps would end the drag starting
    _animation++;
  }

  void _onPointerUp(PointerEvent event) {
    _pointers--;
    // a touch that did not scroll: back to where the scrolling was going
    if (_pointers == 0 && _following) {
      _scrollTo(_controller.subtitleLine.value, animate: true);
    }
  }

  void _onTapLine(int index) {
    _resumeTimer?.cancel();
    _following = true;
    _controller.seekToSubtitleLine(index);
    _scrollTo(index, animate: true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Obx(() {
      return switch (_controller.subtitleLines.value) {
        Loading() => const Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        Success(:final response) when response.isEmpty => Center(
          child: Text(
            '暂无字幕',
            style: TextStyle(color: colorScheme.outline),
          ),
        ),
        Success(:final response) => _buildLines(colorScheme, response),
        Error(:final errMsg) => Center(
          child: TextButton(
            onPressed: _controller.retrySubtitle,
            child: Text(
              '${errMsg ?? '字幕加载失败'}，点击重试',
              textAlign: .center,
            ),
          ),
        ),
      };
    });
  }

  Widget _buildLines(ColorScheme colorScheme, List<SubtitleLine> lines) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxHeight / 2;
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ShaderMask(
              blendMode: .dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: .topCenter,
                end: .bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, 0.15, 0.85, 1],
              ).createShader(bounds),
              child: SuperListView.builder(
                // a new list for other lines, as it keeps the extents it measured
                key: ObjectKey(lines),
                controller: _scrollController,
                listController: _listController,
                padding: .symmetric(vertical: half),
                itemCount: lines.length,
                itemBuilder: (context, index) => _SubtitleLineItem(
                  controller: _controller,
                  index: index,
                  line: lines[index],
                  colorScheme: colorScheme,
                  onTap: _onTapLine,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubtitleLineItem extends StatelessWidget {
  const _SubtitleLineItem({
    required this.controller,
    required this.index,
    required this.line,
    required this.colorScheme,
    required this.onTap,
  });

  final AudioSubtitleMixin controller;
  final int index;
  final SubtitleLine line;
  final ColorScheme colorScheme;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: const .all(.circular(8)),
      child: Padding(
        padding: const .symmetric(horizontal: 8, vertical: 8),
        child: Obx(() {
          final isCurrent = controller.subtitleLine.value == index;
          return AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: isCurrent ? .bold : .normal,
              color: isCurrent
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            child: Text(line.content),
          );
        }),
      ),
    );
  }
}
