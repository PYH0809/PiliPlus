import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:material_ui/material_ui.dart';

class AppBarAni extends StatelessWidget {
  const AppBarAni({
    super.key,
    required this.child,
    required this.controller,
    required this.isTop,
    required this.isFullScreen,
    required this.removeSafeArea,
    this.glass = false,
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;

  /// Whether the bar floats on glass, under a faint shade at the top for its
  /// title and none at the bottom.
  final bool glass;

  static final _topPos = Tween<Offset>(
    begin: const Offset(0.0, -1.0),
    end: Offset.zero,
  );

  static const _topDecoration = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  static const _glassTopDecoration = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0x59000000),
    ],
  );

  static final _bottomPos = Tween<Offset>(
    begin: const Offset(0, 1.2),
    end: Offset.zero,
  );

  static const _bottomDecoration = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  @override
  Widget build(BuildContext context) {
    final bar = _slide();
    if (!glass) {
      return bar;
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) =>
          VideoGlassHidden(hidden: controller.isDismissed, child: child!),
      child: bar,
    );
  }

  Widget _slide() {
    return SlideTransition(
      position: controller.drive(isTop ? _topPos : _bottomPos),
      // A BoxDecoration takes taps over its whole box, so the bars keep one
      // even bare, lest a tap between their panes reach the player.
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: glass
              ? (isTop ? _glassTopDecoration : null)
              : (isTop ? _topDecoration : _bottomDecoration),
        ),
        child: removeSafeArea
            ? child
            : ViewSafeArea(
                left: isFullScreen,
                right: isFullScreen,
                child: child,
              ),
      ),
    );
  }
}
