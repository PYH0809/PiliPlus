import 'package:material_ui/material_ui.dart';

/// How far a header laid over the content covers its top, so that the
/// content's lists start below it while still scrolling under it, and a
/// refresh indicator comes out from under it. 0 where no header overlays.
class HeaderOverlayInset extends InheritedWidget {
  const HeaderOverlayInset({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderOverlayInset>()?.inset ??
      0;

  /// Room at the start of a [CustomScrollView] for the header.
  static Widget sliver(BuildContext context) {
    final inset = of(context);
    return SliverToBoxAdapter(child: SizedBox(height: inset));
  }

  /// Lays [child] out below the header instead, for content that pins
  /// headers of its own, which would pin under it.
  static Widget below(BuildContext context, {required Widget child}) {
    return Padding(
      padding: EdgeInsets.only(top: of(context)),
      child: HeaderOverlayInset(inset: 0, child: child),
    );
  }

  @override
  bool updateShouldNotify(HeaderOverlayInset oldWidget) =>
      inset != oldWidget.inset;
}
