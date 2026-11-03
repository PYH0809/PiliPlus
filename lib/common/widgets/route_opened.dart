import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Calls [onOpened] once the route it sits in has opened, its transition
/// over, or once it has first built if the route is not opening. A page holds back
/// with it what would stall the transition, as calls to the platform: they run
/// on Android's main thread, which then hands out the frames' vsyncs late. A
/// route popped while it opens never calls it.
///
/// Only this widget depends on the route, so the page under it does not
/// rebuild as the route's status changes.
class RouteOpened extends StatefulWidget {
  const RouteOpened({super.key, required this.onOpened, required this.child});

  final VoidCallback onOpened;
  final Widget child;

  @override
  State<RouteOpened> createState() => _RouteOpenedState();
}

class _RouteOpenedState extends State<RouteOpened> {
  bool _looked = false;
  Animation<double>? _opening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_looked) {
      return;
    }
    _looked = true;
    final animation = ModalRoute.of(context)?.animation;
    // A route being pushed can report itself completed as it first builds,
    // before it sets off: a frame on, it is moving if it opens.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (animation == null || animation.status != AnimationStatus.forward) {
        widget.onOpened();
      } else {
        _opening = animation..addStatusListener(_onStatus);
      }
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward) {
      return;
    }
    _stop();
    if (status == AnimationStatus.completed) {
      widget.onOpened();
    }
  }

  void _stop() {
    _opening?.removeStatusListener(_onStatus);
    _opening = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
