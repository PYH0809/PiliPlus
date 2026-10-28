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
/// rather than fading, as [drag] pulls the image away to close the gallery
/// and while the image is [zoomed] in, and comes back as either lets go.
class GalleryGlass extends StatefulWidget {
  const GalleryGlass({
    super.key,
    required this.drag,
    required this.zoomed,
    this.overVideo = false,
    required this.child,
  });

  /// How far the image is pulled away, as a share of the screen's height.
  final Animation<double> drag;
  final ValueListenable<bool> zoomed;

  /// Whether a video plays under it, as a live photo's: a texture, which the
  /// host cannot capture, so the pane is then a [VideoGlass], which sees it.
  final bool overVideo;
  final Widget child;

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
      listenable: Listenable.merge([widget.drag, _shown]),
      builder: (context, child) {
        final t =
            _shown.value * (1 - widget.drag.value / _kDragAway).clamp(0.0, 1.0);
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
        if (widget.overVideo) {
          // As the player's notes over the video.
          return VideoGlass.capsule(note: true, t: t, child: content);
        }
        return LiquidGlass(
          style: LiquidGlassStyle.regular(colorScheme).scale(t),
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
