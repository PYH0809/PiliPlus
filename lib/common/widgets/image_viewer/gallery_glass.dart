import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

// How far, as a share of the screen's height, the image is pulled to close
// the gallery when the glass has stepped aside: half the way to closing it.
const double _kDragAway = 0.1;

final _showSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
);

/// A capsule of glass floating over the gallery's image, holding [child], as
/// the page count.
///
/// The gallery is black in either theme, so the glass is dark, as the
/// player's is, and its text light. It steps aside, easing out by bending
/// rather than fading, as [drag] pulls the image away to close the gallery,
/// while the image is [zoomed] in and as [turning] asks, and comes back as
/// each lets go.
class GalleryGlass extends StatefulWidget {
  const GalleryGlass({
    super.key,
    required this.drag,
    required this.zoomed,
    this.turning,
    this.video,
    required this.child,
  });

  /// How far the image is pulled away, as a share of the screen's height.
  final Animation<double> drag;
  final ValueListenable<bool> zoomed;

  /// How far, from 0 to 1, to step aside as a page turns under it, as
  /// [turningAway] answers.
  final ValueListenable<double>? turning;

  /// Keys a box holding the video under it while one plays, as a live
  /// photo's: a texture, which the host cannot capture, so the pane is then
  /// a [VideoGlass], which draws the video again itself.
  final GlobalKey? video;
  final Widget child;

  /// How far the glass steps aside at [page], fractional while a page
  /// turns, where [isVideo] says which pages hold a video: from a quarter of
  /// the way into a turn to or from one, as over both pages at once neither
  /// [VideoGlass] nor the host's glass would show them both.
  static double turningAway(double page, bool Function(int index) isVideo) {
    final from = page.floor();
    if (from == page || !(isVideo(from) || isVideo(from + 1))) {
      return 0;
    }
    return ((page - page.roundToDouble()).abs() * 4).clamp(0.0, 1.0);
  }

  @override
  State<GalleryGlass> createState() => _GalleryGlassState();
}

class _GalleryGlassState extends State<GalleryGlass>
    with SingleTickerProviderStateMixin {
  late final _shown = GlassSpring(this, widget.zoomed.value ? 0 : 1);
  late ColorScheme _colorScheme;

  @override
  void initState() {
    super.initState();
    widget.zoomed.addListener(_onZoom);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = VideoGlass.controlsTheme(Theme.of(context)).colorScheme;
  }

  @override
  void didUpdateWidget(GalleryGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomed != widget.zoomed) {
      oldWidget.zoomed.removeListener(_onZoom);
      widget.zoomed.addListener(_onZoom);
      _onZoom();
    }
  }

  @override
  void dispose() {
    widget.zoomed.removeListener(_onZoom);
    _shown.dispose();
    super.dispose();
  }

  void _onZoom() {
    final target = widget.zoomed.value ? 0.0 : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown.jumpTo(target);
    } else {
      _shown.springTo(target, _showSpring);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.drag, _shown, widget.turning]),
      builder: (context, child) {
        final t =
            _shown.value *
            (1 - widget.drag.value / _kDragAway).clamp(0.0, 1.0) *
            (1 - (widget.turning?.value ?? 0));
        // Gone, it leaves the host nothing to capture for it.
        if (t <= 0) {
          return const SizedBox.shrink();
        }
        final colorScheme = _colorScheme;
        final content = Padding(
          padding: const .symmetric(horizontal: 14, vertical: 6),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: .w500,
              // So that the capsule keeps its width as the page turns.
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colorScheme.onSurface.withValues(alpha: t),
            ),
            child: child!,
          ),
        );
        final style = LiquidGlassStyle.regular(colorScheme);
        if (widget.video case final video?) {
          // As thick as the glass over an image, which the player's clear
          // glass is not over the black around the video. Not one of the
          // player's notes, which their own switch may leave a bare tint.
          return VideoGlassSource(
            video: video,
            child: VideoGlass.capsule(
              t: t,
              style: style,
              child: content,
            ),
          );
        }
        return LiquidGlass(
          style: style.scale(t),
          shadows: [
            for (final shadow in floatingGlassShadows(colorScheme))
              shadow.copyWith(
                color: shadow.color.withValues(alpha: shadow.color.a * t),
              ),
          ],
          child: content,
        );
      },
      child: widget.child,
    );
  }
}
