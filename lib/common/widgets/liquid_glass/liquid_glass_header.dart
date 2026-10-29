import 'package:material_ui/material_ui.dart';

/// A header laid over content that scrolls under it, as iOS's bars over
/// their scroll edge: [child], usually glass, over a soft fade of the surface
/// that runs [fade] past its bottom and lets touches through.
class LiquidGlassHeader extends StatelessWidget {
  const LiquidGlassHeader({
    super.key,
    required this.child,
    this.fade = 16,
  });

  final Widget child;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _EdgeFade(begin: Alignment.topCenter)),
        Padding(
          padding: EdgeInsets.only(bottom: fade),
          child: child,
        ),
      ],
    );
  }
}

/// [LiquidGlassHeader] at the bottom edge, as iOS's toolbars: [child] over
/// the same fade, running [fade] above its top.
class LiquidGlassFooter extends StatelessWidget {
  const LiquidGlassFooter({
    super.key,
    required this.child,
    this.fade = 16,
  });

  final Widget child;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: _EdgeFade(begin: Alignment.bottomCenter),
        ),
        Padding(
          padding: EdgeInsets.only(top: fade),
          child: child,
        ),
      ],
    );
  }
}

/// The surface fading out from the edge at [begin], letting touches through.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.begin});

  final Alignment begin;

  @override
  Widget build(BuildContext context) {
    final surface = ColorScheme.of(context).surface;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: -begin,
            colors: [
              surface.withValues(alpha: 0.85),
              surface.withValues(alpha: 0.6),
              surface.withValues(alpha: 0),
            ],
            stops: const [0, 0.6, 1],
          ),
        ),
      ),
    );
  }
}
