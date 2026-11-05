import 'package:PiliPlus/common/widgets/video_card/video_expand.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// [placeholder] while the page grows out of its card, [child] [frames]
/// frames after it has landed: the opening's frames then stay light enough
/// for the expand to run smooth. A page opened any other way, or already
/// landed, builds [child] at once.
class AfterLanding extends StatefulWidget {
  const AfterLanding({
    super.key,
    required this.placeholder,
    required this.child,
    this.frames = 1,
  });

  final Widget placeholder;
  final Widget child;

  /// How many frames after landing [child] builds, so that two of these do
  /// not build in the same frame.
  final int frames;

  @override
  State<AfterLanding> createState() => _AfterLandingState();
}

class _AfterLandingState extends State<AfterLanding> {
  bool _ready = false;
  ValueListenable<bool>? _landed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready || _landed != null) return;
    final landed = VideoExpandRoute.of(context)?.landed;
    if (landed == null || landed.value) {
      _ready = true;
      return;
    }
    _landed = landed..addListener(_handleLanded);
  }

  void _handleLanded() {
    if (_landed!.value) {
      _landed!.removeListener(_handleLanded);
      _reveal(1);
    }
  }

  void _reveal(int frame) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || _ready) return;
        if (frame < widget.frames) {
          _reveal(frame + 1);
        } else {
          setState(() => _ready = true);
        }
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    _landed?.removeListener(_handleLanded);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : widget.placeholder;
}
