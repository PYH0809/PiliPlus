import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class CustomToast extends StatelessWidget {
  const CustomToast(this.msg, {super.key});

  final String msg;

  static double toastOpacity = Pref.defaultToastOp;

  static final bool _glass = Pref.liquidGlass;

  /// Shows [msg] over the player's video, as a skip in full screen. On glass
  /// it is a capsule of the video's glass, as the player's notes are: the
  /// toasts' own glass lies above the host, so over the video it showed a
  /// bare tint, the video sharp under it.
  static void showOverVideo(String msg, {Alignment? alignment}) {
    if (!GlassSurfaces.installed) {
      SmartDialog.showToast(msg, alignment: alignment);
      return;
    }
    SmartDialog.showToast(
      msg,
      alignment: alignment,
      builder: (_) => Padding(
        padding: const .symmetric(horizontal: 22, vertical: 15),
        child: Text(
          msg,
          textAlign: .center,
          style: const TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: .w500,
            color: Colors.white,
          ),
        ),
      ),
      // The glass eases in and out through its t: SmartDialog's fade, an
      // Opacity over the backdrop filter, would break it. Its opacity
      // setting thins it as it does the toasts' own glass.
      animationBuilder: (controller, child, _) => AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Padding(
          padding: const .symmetric(horizontal: 24),
          child: VideoGlass.capsule(
            note: true,
            t: controller.value * toastOpacity,
            child: Opacity(opacity: controller.value, child: child),
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    if (_glass) {
      // A capsule of glass at iOS's size, as the nav bar; it frosts rather
      // than bends, as toasts show above the glass host. Its opacity setting
      // thins the glass as it does the bubble.
      return Padding(
        padding: .fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewPaddingOf(context).bottom + 30,
        ),
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
          child: Padding(
            padding: const .symmetric(horizontal: 22, vertical: 15),
            child: Text(
              msg,
              textAlign: .center,
              style: TextStyle(
                fontSize: 15,
                height: 20 / 15,
                fontWeight: .w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
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
