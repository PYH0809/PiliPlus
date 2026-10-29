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
