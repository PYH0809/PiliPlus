import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// Tabs that follow the finger. Inside another's tab, a swipe past the first
/// or last of them turns that other's tab instead. [isDxAllowed] says where
/// across them a swipe may start, as on a panel that closes from its edges.
Widget tabBarView({
  required List<Widget> children,
  TabController? controller,
  HitTestBehavior hitTestBehavior = .opaque,
  bool Function(double dx)? isDxAllowed,
}) => _TabBarView(
  controller: controller,
  hitTestBehavior: hitTestBehavior,
  isDxAllowed: isDxAllowed,
  children: children,
);

class _TabBarView extends StatefulWidget {
  const _TabBarView({
    required this.controller,
    required this.hitTestBehavior,
    required this.isDxAllowed,
    required this.children,
  });

  final TabController? controller;
  final HitTestBehavior hitTestBehavior;
  final bool Function(double dx)? isDxAllowed;
  final List<Widget> children;

  @override
  State<_TabBarView> createState() => _TabBarViewState();
}

class _TabBarViewState extends State<_TabBarView> {
  // Read as a drag starts, by a recognizer made once: kept here, as the tabs
  // and the widget come and go, rather than in it.
  late TabController _controller;

  bool _canTurn(bool forward) {
    // Where the tabs are, in tabs; a settled drag can stop a hair short.
    final at = _controller.animation?.value ?? _controller.index.toDouble();
    const slack = 0.01;
    return forward ? at < _controller.length - 1 - slack : at > slack;
  }

  bool _isDxAllowed(double dx) => widget.isDxAllowed?.call(dx) ?? true;

  TabBarViewDragGestureRecognizer _recognizer() =>
      TabBarViewDragGestureRecognizer(
        canTurn: _canTurn,
        isDxAllowed: _isDxAllowed,
      );

  @override
  Widget build(BuildContext context) {
    _controller = widget.controller ?? DefaultTabController.of(context);
    return TabBarView(
      controller: widget.controller,
      physics: tabBarScrollPhysics,
      hitTestBehavior: widget.hitTestBehavior,
      horizontalDragGestureRecognizer: _recognizer,
      children: widget.children,
    );
  }
}

SpringDescription kSpringDescription = _customSpringDescription();

SpringDescription _customSpringDescription() {
  final List<double> springDescription = Pref.springDescription;
  return SpringDescription(
    mass: springDescription[0],
    stiffness: springDescription[1],
    damping: springDescription[2],
  );
}

const tabBarScrollPhysics = _TabBarViewScrollPhysics();

class _TabBarViewScrollPhysics extends ClampingScrollPhysics {
  const _TabBarViewScrollPhysics({super.parent});

  @override
  _TabBarViewScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _TabBarViewScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => kSpringDescription;
}

mixin ReloadMixin {
  late bool reload = false;
}

class ReloadScrollPhysics extends AlwaysScrollableScrollPhysics {
  const ReloadScrollPhysics({super.parent, required this.controller});

  final ReloadMixin controller;

  @override
  ReloadScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ReloadScrollPhysics(
      parent: buildParent(ancestor),
      controller: controller,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (controller.reload) {
      controller.reload = false;
      return 0;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

final platformClampingPhysics = PlatformUtils.isDarwin
    ? const BouncingScrollPhysicsExt()
    : const ClampingScrollPhysics();

final platformAlwaysClampingPhysics = PlatformUtils.isDarwin
    ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysicsExt())
    : const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());

class BouncingScrollPhysicsExt extends BouncingScrollPhysics
    with ClampingBoundaryMixin {
  const BouncingScrollPhysicsExt({super.parent});

  @override
  BouncingScrollPhysicsExt applyTo(ScrollPhysics? ancestor) {
    return BouncingScrollPhysicsExt(parent: buildParent(ancestor));
  }
}

/// [ClampingScrollPhysics.applyBoundaryConditions]
mixin ClampingBoundaryMixin on ScrollPhysics {
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      // Underscroll.
      return value - position.pixels;
    }
    if (position.maxScrollExtent <= position.pixels &&
        position.pixels < value) {
      // Overscroll.
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      // Hit top edge.
      return value - position.minScrollExtent;
    }
    if (position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < value) {
      // Hit bottom edge.
      return value - position.maxScrollExtent;
    }
    return 0.0;
  }
}
