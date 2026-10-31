import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class CustomToast extends StatelessWidget {
  const CustomToast(this.msg, {super.key});

  final String msg;

  static double toastOpacity = Pref.defaultToastOp;

  static final bool _glass = Pref.liquidGlass;

  /// Whether the player is in full screen, in place of one; tests set it.
  @visibleForTesting
  static RxBool? debugFullScreen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    if (_glass) {
      final fullScreen =
          debugFullScreen ?? PlPlayerController.instance?.isFullScreen;
      final video = VideoGlassSource.player?.video.currentContext;
      if (fullScreen == null || video == null) {
        return _onGlass(context, colorScheme, false);
      }
      // A toast lies over the video while the player is in full screen and
      // on show, as under a menu or a panel, not under a page pushed over
      // it, as the live room's 弹幕屏蔽. One shown follows both: as full
      // screen ends, on a desktop, whose window stays as it is, and as a
      // page covers the player or uncovers it.
      return _PlayerOnShow(
        video: video,
        builder: (onShow) => Obx(
          () => _onGlass(context, colorScheme, fullScreen.value && onShow),
        ),
      );
    }
    return Container(
      margin: .only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 30,
      ),
      padding: const .symmetric(horizontal: 17, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: toastOpacity),
        borderRadius: const .all(.circular(20)),
      ),
      child: Text(
        msg,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _onGlass(
    BuildContext context,
    ColorScheme colorScheme,
    bool overVideo,
  ) {
    final padding = EdgeInsets.fromLTRB(
      24,
      0,
      24,
      MediaQuery.viewPaddingOf(context).bottom + 30,
    );
    Widget text(Color color) => Padding(
      padding: const .symmetric(horizontal: 22, vertical: 15),
      child: Text(
        msg,
        textAlign: .center,
        style: TextStyle(
          fontSize: 15,
          height: 20 / 15,
          fontWeight: .w500,
          color: color,
        ),
      ),
    );
    if (overVideo) {
      // In full screen a toast lies over the video, which the toasts' own
      // glass, above the host, cannot read: it showed a bare tint there,
      // the video sharp under it. A capsule of the video's glass, white
      // text on it, as the player's notes are. It draws the player's video
      // itself rather than reading the screen behind it, so SmartDialog's
      // fade over it leaves it whole, and it costs no pass over the whole
      // screen every frame it shows. Its opacity setting thins it as it
      // does the toasts' own glass.
      return Padding(
        padding: padding,
        child: VideoGlassSource.overPlayer(
          child: VideoGlass.capsule(
            note: true,
            t: toastOpacity,
            child: text(Colors.white),
          ),
        ),
      );
    }
    // A capsule of glass at iOS's size, as the nav bar; it frosts rather
    // than bends, as toasts show above the glass host. Its opacity setting
    // thins the glass as it does the bubble.
    return Padding(
      padding: padding,
      child: LiquidGlass(
        style: LiquidGlassStyle.pill(colorScheme).scale(toastOpacity),
        // A pill on one line; rounded as one on more.
        borderRadius: const .all(.circular(25)),
        shadows: [
          for (final shadow in floatingGlassShadows(colorScheme))
            shadow.copyWith(
              color: shadow.color.withValues(
                alpha: shadow.color.a * toastOpacity,
              ),
            ),
        ],
        child: text(colorScheme.onSurface),
      ),
    );
  }
}

/// Builds with whether the page of [video] is on show, and again as a page
/// pushed over it or popped changes it.
class _PlayerOnShow extends StatefulWidget {
  const _PlayerOnShow({required this.video, required this.builder});

  final BuildContext video;
  final Widget Function(bool onShow) builder;

  @override
  State<_PlayerOnShow> createState() => _PlayerOnShowState();
}

class _PlayerOnShowState extends State<_PlayerOnShow> {
  late final _mode = TickerMode.getValuesNotifier(widget.video);

  @override
  void initState() {
    super.initState();
    _mode.addListener(_onChange);
  }

  // The navigator changes it as it builds, which this, out of its tree,
  // must not interrupt: it builds again once that frame is done.
  void _onChange() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _mode.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_mode.value.enabled);
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget(this.msg, {super.key});

  ///loading msg
  final String msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const .symmetric(horizontal: 30, vertical: 20),
      decoration: BoxDecoration(
        color: theme.dialogTheme.backgroundColor,
        borderRadius: const .all(.circular(15)),
      ),
      child: Column(
        spacing: 20,
        mainAxisSize: .min,
        children: [
          //loading animation
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(onSurfaceVariant),
          ),
          //msg
          Text(msg, style: TextStyle(color: onSurfaceVariant)),
        ],
      ),
    );
  }
}

class NotifyWarning extends StatelessWidget {
  const NotifyWarning(this.msg, {super.key});

  final String msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const .all(.circular(8)),
        color: theme.dialogTheme.backgroundColor,
      ),
      padding: const .symmetric(horizontal: 20, vertical: 10),
      child: Column(
        spacing: 5,
        mainAxisSize: .min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 22,
            color: onSurfaceVariant,
          ),
          Text(msg, style: TextStyle(color: onSurfaceVariant)),
        ],
      ),
    );
  }
}
