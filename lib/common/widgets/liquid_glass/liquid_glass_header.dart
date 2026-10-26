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
    final surface = ColorScheme.of(context).surface;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    surface.withValues(alpha: 0.85),
                    surface.withValues(alpha: 0.6),
                    surface.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: fade),
          child: child,
        ),
      ],
    );
  }
}
