import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, BoxParentData, RenderShiftedBox;
import 'package:material_ui/material_ui.dart';

/// 听视频's playback controls on glass, as iOS 26's player lays them out:
/// [progress] on a capsule between [position] and [duration], and under it
/// the play mode and the playlist on circles either side of previous, play
/// and next, together on one taller capsule, the play button the largest.
///
/// It is [height] tall and at most [maxWidth] wide, centered. In a window
/// narrower than the buttons they shrink, and the controls with them.
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

  /// How narrow the progress bar gets at least: the times beside it shrink
  /// first, in a narrow window or at a large text size.
  static const double minProgressWidth = 64;

  // As the title bar's, so that the times keep to the capsule's height.
  static const double _maxTimeTextScale = 1.34;

  // The two circles and the capsule between them, a little apart.
  static const double _minButtonsWidth =
      2 * GlassButtonGroup.thickness + 3 * transportSize + 2 * 8;

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
    final buttons = Row(
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
                tooltip: playPause.status.isForwardOrCompleted ? '暂停' : '播放',
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
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: _maxTimeTextScale,
                          child: DefaultTextStyle(
                            style: timeStyle,
                            child: CustomMultiChildLayout(
                              delegate: _ProgressLayout(),
                              children: [
                                LayoutId(
                                  id: _ProgressSlot.position,
                                  child: FittedBox(
                                    fit: .scaleDown,
                                    child: position,
                                  ),
                                ),
                                LayoutId(
                                  id: _ProgressSlot.bar,
                                  child: _ThickHitTarget(child: progress),
                                ),
                                LayoutId(
                                  id: _ProgressSlot.duration,
                                  child: FittedBox(
                                    fit: .scaleDown,
                                    child: duration,
                                  ),
                                ),
                                if (trailing != null)
                                  LayoutId(
                                    id: _ProgressSlot.trailing,
                                    child: trailing!,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: gap),
              LayoutBuilder(
                // Narrower than the buttons, as a small window sideways, they
                // shrink together.
                builder: (context, constraints) => FittedBox(
                  fit: .scaleDown,
                  child: SizedBox(
                    width: math.max(constraints.maxWidth, _minButtonsWidth),
                    child: buttons,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProgressSlot { position, bar, duration, trailing }

/// The progress' capsule from the start: the position, the bar, the
/// duration and the trailing button, each centered on the height. The bar
/// takes what the others leave, but never less than
/// [AudioGlassControls.minProgressWidth]: the times scale down to make room.
class _ProgressLayout extends MultiChildLayoutDelegate {
  static const double _gap = 12;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final trailing = hasChild(_ProgressSlot.trailing)
        ? layoutChild(_ProgressSlot.trailing, loose)
        : Size.zero;
    final forTimes =
        size.width -
        trailing.width -
        2 * _gap -
        AudioGlassControls.minProgressWidth;
    final time = BoxConstraints(
      maxWidth: forTimes.clamp(0, double.infinity) / 2,
      maxHeight: size.height,
    );
    final position = layoutChild(_ProgressSlot.position, time);
    final duration = layoutChild(_ProgressSlot.duration, time);
    final barWidth =
        (size.width -
                trailing.width -
                position.width -
                duration.width -
                2 * _gap)
            .clamp(0.0, double.infinity);
    layoutChild(
      _ProgressSlot.bar,
      BoxConstraints.tightFor(width: barWidth, height: size.height),
    );

    double middle(Size child) => (size.height - child.height) / 2;
    var x = 0.0;
    positionChild(_ProgressSlot.position, Offset(x, middle(position)));
    x += position.width + _gap;
    positionChild(_ProgressSlot.bar, Offset(x, 0));
    x += barWidth + _gap;
    positionChild(_ProgressSlot.duration, Offset(x, middle(duration)));
    x += duration.width;
    if (hasChild(_ProgressSlot.trailing)) {
      positionChild(_ProgressSlot.trailing, Offset(x, middle(trailing)));
    }
  }

  @override
  bool shouldRelayout(_ProgressLayout oldDelegate) => false;
}

/// [child], a thin bar, across the middle of the capsule's height, taking a
/// touch anywhere on that height as one on the bar, so that it can be dragged
/// from above or below its line as well.
class _ThickHitTarget extends SingleChildRenderObjectWidget {
  const _ThickHitTarget({required super.child});

  @override
  RenderShiftedBox createRenderObject(BuildContext context) =>
      _RenderThickHitTarget();
}

class _RenderThickHitTarget extends RenderShiftedBox {
  _RenderThickHitTarget() : super(null);

  BoxParentData get _childData => child!.parentData! as BoxParentData;

  @override
  void performLayout() {
    final child = this.child!
      ..layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.biggest;
    _childData.offset = Offset(0, (size.height - child.size.height) / 2);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    final child = this.child!;
    final offset = _childData.offset;
    // The bar sees the touch where it really is, but takes it at any height.
    final onBar = Offset(position.dx, offset.dy + child.size.height / 2);
    return result.addWithPaintOffset(
      offset: offset,
      position: onBar,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}
