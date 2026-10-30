import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart' show DetailItem;
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/pages/audio/subtitle/lyrics_list.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_mixin.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// The subtitles in place of the cover: a small cover and the title, which
/// go back to the cover when tapped, the language, then the lines.
class AudioSubtitlePanel extends StatelessWidget {
  const AudioSubtitlePanel({
    super.key,
    required this.controller,
    required this.item,
    this.padding = .zero,
  });

  final AudioSubtitleMixin controller;
  final DetailItem item;

  /// What the bars floating on glass cover: the lines stop and fade out
  /// above them, as they are text to read.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: padding,
      child: Column(
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
      ),
    );
  }
}

/// Switches between the cover and the subtitles on a tap anywhere on [child]
/// that its own controls do not take, as music players do: the cover and
/// the room around it, the room beside and between the lines, and the
/// page's [margin] beside it. A tap under the glass bars, within [padding],
/// does nothing, nor one that stops a list scrolling. From the keyboard it
/// takes focus, with a ring, and switches on Enter or Space.
class AudioSubtitleToggle extends StatefulWidget {
  const AudioSubtitleToggle({
    super.key,
    required this.showing,
    required this.onToggle,
    this.padding = .zero,
    this.margin = .zero,
    required this.child,
  });

  /// Whether the subtitles show.
  final bool showing;
  final VoidCallback onToggle;

  /// What the glass bars cover, as [child]'s lists keep it clear.
  final EdgeInsets padding;

  /// The room around [child], taking taps but not the ring.
  final EdgeInsets margin;
  final Widget child;

  @override
  State<AudioSubtitleToggle> createState() => _AudioSubtitleToggleState();
}

class _AudioSubtitleToggleState extends State<AudioSubtitleToggle> {
  /// Lists under it now scrolling, and whether one was as the touch began.
  /// One that goes while it scrolls, as the lines do for the cover or
  /// another language, says no end: it leaves when it is no longer mounted.
  final _scrolling = <BuildContext>{};
  bool _stopsScroll = false;

  /// A list's scroll ended in the event being handled: a touch holding it
  /// still ends it before this hears of the touch.
  bool _endedNow = false;

  bool _focusRing = false;

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.onToggle(),
    ),
  };

  bool _onScroll(ScrollNotification notification) {
    switch (notification) {
      case ScrollStartNotification(:final context?):
        _scrolling.add(context);
      case ScrollEndNotification(:final context):
        _scrolling.remove(context);
        _endedNow = true;
        scheduleMicrotask(() => _endedNow = false);
    }
    return false;
  }

  void _onTapUp(TapUpDetails details) {
    final size = context.size;
    if (_stopsScroll ||
        size == null ||
        !widget.padding
            .deflateRect(Offset.zero & size)
            .contains(details.localPosition)) {
      return;
    }
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final inset = widget.padding + widget.margin;
    // Without the icon it took the place of, its action for screen readers
    // and the keyboard.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: widget.showing ? '显示封面' : '显示字幕',
      onTap: widget.onToggle,
      child: FocusableActionDetector(
        actions: _actions,
        onShowFocusHighlight: (value) => setState(() => _focusRing = value),
        child: Listener(
          onPointerDown: (_) {
            _scrolling.removeWhere((context) => !context.mounted);
            _stopsScroll = _scrolling.isNotEmpty || _endedNow;
          },
          child: GestureDetector(
            behavior: .opaque,
            excludeFromSemantics: true,
            onTapUp: _onTapUp,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(padding: widget.margin, child: widget.child),
                  ),
                  if (_focusRing)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          padding: inset,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: ColorScheme.of(context).primary,
                                width: 2,
                              ),
                              borderRadius: const .all(.circular(16)),
                            ),
                          ),
                        ),
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
