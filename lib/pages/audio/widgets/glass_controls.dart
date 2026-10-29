import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// 听视频's playback controls on glass, as iOS 26's player lays them out:
/// [progress] on a capsule between [position] and [duration], and under it
/// the play mode and the playlist on circles either side of previous, play
/// and next, together on one taller capsule, the play button the largest.
///
/// It is [height] tall and at most [maxWidth] wide, centered.
class AudioGlassControls extends StatelessWidget {
  const AudioGlassControls({
    super.key,
    required this.position,
    required this.progress,
    required this.duration,
    this.trailing,
    required this.playModeIcon,
    required this.onPlayMode,
    required this.onPrevious,
    required this.playPause,
    required this.onPlayPause,
    required this.onNext,
    required this.onPlaylist,
  });

  /// How thick the capsule of previous, play and next is, and how wide each
  /// of them.
  static const double transportSize = 56;
  static const double gap = 12;
  static const double height = GlassButtonGroup.thickness + gap + transportSize;
  static const double maxWidth = 480;

  final Widget position;
  final Widget progress;
  final Widget duration;

  /// After [duration] on the progress' capsule, as the desktop's volume.
  final Widget? trailing;

  final Widget playModeIcon;
  final VoidCallback onPlayMode;
  final VoidCallback onPrevious;

  /// How far the play button has turned into pause, 1 while playing.
  final Animation<double> playPause;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPlaylist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final timeStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: LiquidGlassGroup(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              // A touch anywhere on the capsule is the progress', not the
              // content's under the glass.
              Listener(
                behavior: .opaque,
                child: SizedBox(
                  height: GlassButtonGroup.thickness,
                  child: LiquidGlass(
                    style: LiquidGlassStyle.regular(colorScheme),
                    shadows: floatingGlassShadows(colorScheme),
                    child: Theme(
                      data: GlassSurfaces.withoutRipples(theme),
                      child: Padding(
                        padding: .only(
                          left: 18,
                          right: trailing == null ? 18 : 4,
                        ),
                        child: Row(
                          children: [
                            DefaultTextStyle(style: timeStyle, child: position),
                            const SizedBox(width: 12),
                            Expanded(child: progress),
                            const SizedBox(width: 12),
                            DefaultTextStyle(style: timeStyle, child: duration),
                            ?trailing,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: gap),
              Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  GlassButtonGroup(
                    glass: true,
                    children: [
                      IconButton(
                        tooltip: '播放设置',
                        onPressed: onPlayMode,
                        iconSize: 24,
                        icon: playModeIcon,
                      ),
                    ],
                  ),
                  GlassButtonGroup(
                    glass: true,
                    buttonSize: transportSize,
                    children: [
                      IconButton(
                        tooltip: '上一个',
                        onPressed: onPrevious,
                        color: colorScheme.onSurface,
                        icon: const Icon(Icons.skip_previous_rounded, size: 32),
                      ),
                      ListenableBuilder(
                        listenable: playPause,
                        builder: (context, _) => IconButton(
                          tooltip: playPause.status.isForwardOrCompleted
                              ? '暂停'
                              : '播放',
                          onPressed: onPlayPause,
                          color: colorScheme.onSurface,
                          icon: AnimatedIcon(
                            size: 40,
                            icon: AnimatedIcons.play_pause,
                            progress: playPause,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '下一个',
                        onPressed: onNext,
                        color: colorScheme.onSurface,
                        icon: const Icon(Icons.skip_next_rounded, size: 32),
                      ),
                    ],
                  ),
                  GlassButtonGroup(
                    glass: true,
                    children: [
                      IconButton(
                        tooltip: '播放列表',
                        onPressed: onPlaylist,
                        iconSize: 24,
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
