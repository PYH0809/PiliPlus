import 'dart:math' show min;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/header_overlay_inset.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/image_viewer/hero.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_app_bar.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_header.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/menu_entries.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show platformClampingPhysics;
import 'package:PiliPlus/common/widgets/selection_text.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pb.dart';
import 'package:PiliPlus/models/common/image_preview_type.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/pages/audio/backdrop/audio_backdrop.dart';
import 'package:PiliPlus/pages/audio/controller.dart';
import 'package:PiliPlus/pages/audio/volume_button.dart';
import 'package:PiliPlus/pages/audio/widgets/glass_controls.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart'
    show showPlayerVolumeDialog;
import 'package:PiliPlus/pages/video/widgets/header_control.dart'
    show HeaderControlState;
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class AudioPage extends StatefulWidget {
  const AudioPage({super.key});

  @override
  State<AudioPage> createState() => _AudioPageState();

  /// Makes the page's controller in place of [AudioController.new], for a
  /// test to give it one that neither fetches nor plays.
  @visibleForTesting
  static AudioController Function()? debugController;

  static void toAudioPage({
    int? id,
    required int oid,
    List<int>? subId,
    required int itemType,
    required PlaylistSource from,
    String? heroTag,
    Duration? start,
    String? audioUrl,
    int? extraId,
  }) => Get.toNamed(
    '/audio',
    arguments: {
      'id': ?id,
      'oid': oid,
      'subId': ?subId,
      'from': from,
      'itemType': itemType,
      'heroTag': ?heroTag,
      'start': ?start,
      'audioUrl': ?audioUrl,
      'extraId': ?extraId,
    },
  );
}

extension _ListOrderExt on ListOrder {
  String get title => const ['无序', '正序', '倒序', '随机'][value];
}

class _AudioPageState extends State<AudioPage>
    with RouteAware, RouteAwareMixin {
  final _controller = Get.put(
    AudioPage.debugController?.call() ?? AudioController(),
    tag: Utils.generateRandomString(8),
  );

  @override
  void didPushNext() {
    super.didPushNext();
    _controller.isCovered = true;
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _controller.onUncovered();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.didChangeDependencies(context);
  }

  /// Dark in either theme, as iOS's Now Playing is, over the cover's
  /// colors; the bar clear, as the page is, to show them.
  static ThemeData _pageTheme(ThemeData theme) {
    final dark = VideoGlass.darkTheme(theme);
    return dark.copyWith(
      appBarTheme: dark.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _pageTheme(Theme.of(context)),
      child: Stack(
        children: [
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final placeholder = ColorScheme.of(context).surface;
                return Obx(() {
                  final cover = _controller.audioItem.value?.arc.cover;
                  return AudioBackdrop(
                    image: cover == null || cover.isEmpty
                        ? null
                        : CachedNetworkImageProvider(cover.http2https),
                    placeholder: placeholder,
                  );
                });
              },
            ),
          ),
          Builder(builder: _buildPage),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final isPortrait = MediaQuery.sizeOf(context).isPortrait;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        actions: [
          if (_controller.isUgc && _controller.enableSponsorBlock)
            Obx(() {
              if (_controller.segmentProgressList.isNotEmpty) {
                return IconButton(
                  tooltip: '片段信息',
                  onPressed: _controller.showSBDetail,
                  icon: const Icon(MdiIcons.advertisements, size: 22),
                );
              }
              return const SizedBox.shrink();
            }),
          Builder(
            builder: (context) {
              return PopupMenuButton<ListOrder>(
                tooltip: '排序',
                icon: const Icon(Icons.sort, size: 22),
                initialValue: _controller.order,
                onSelected: (value) {
                  _controller.onChangeOrder(value);
                  (context as Element).markNeedsBuild();
                },
                itemBuilder: (context) => ListOrder.values
                    .map((e) => PopupMenuItem(value: e, child: Text(e.title)))
                    .toList(),
              );
            },
          ),
          IconButton(
            tooltip: '定时关闭',
            onPressed: () => shutdownTimerService
              ..onPause ??= _controller.onPause
              ..isPlaying ??= _controller.isPlayingOrPending
              ..showScheduleExitDialog(
                context,
                isFullScreen: false,
              ),
            icon: const Icon(Icons.schedule, size: 22),
          ),
          Obx(() {
            final audioItem = _controller.audioItem.value;
            if (_controller.isUgc || (audioItem?.hasMv ?? false)) {
              return PopupMenuButton<void>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert, size: 22),
                itemBuilder: (_) => _moreEntries(audioItem),
              );
            }
            return const SizedBox.shrink();
          }),
          const SizedBox(width: 5),
        ],
      ),
      body: GlassAppBar.enabled
          ? Builder(builder: _buildGlassBody)
          : Padding(
              padding: EdgeInsets.only(
                left: 20 + padding.left,
                right: 20 + padding.right,
                bottom: 30 + padding.bottom,
              ),
              child: isPortrait
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInfo(colorScheme, .zero)),
                        const SizedBox(height: 25),
                        _buildProgressBar(colorScheme),
                        _buildDuration(colorScheme),
                        _buildControls(),
                      ],
                    )
                  : Row(
                      spacing: 12,
                      children: [
                        Expanded(
                          child: _buildInfo(colorScheme, .zero),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildProgressBar(colorScheme),
                              _buildDuration(colorScheme),
                              _buildControls(),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  /// With glass on, the content takes the whole page, under the title bar
  /// and, upright, under the controls floating on glass at the bottom, its
  /// lists kept clear of both by the padding [_buildInfo] gets. Sideways
  /// the controls stand on glass beside it.
  Widget _buildGlassBody(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final top = HeaderOverlayInset.of(context);
    final controls = _buildGlassControls(colorScheme);
    final sides = EdgeInsets.only(
      left: 20 + padding.left,
      right: 20 + padding.right,
    );
    if (MediaQuery.sizeOf(context).isPortrait) {
      final bottom = padding.bottom + _glassControlsBottom;
      return Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: sides,
              child: _buildInfo(
                colorScheme,
                EdgeInsets.only(
                  top: top,
                  bottom: bottom + AudioGlassControls.height + _glassFade,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidGlassFooter(
              fade: _glassFade,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _glassControlsSide + padding.left,
                  0,
                  _glassControlsSide + padding.right,
                  bottom,
                ),
                child: controls,
              ),
            ),
          ),
        ],
      );
    }
    final bottom = 30 + padding.bottom;
    return Padding(
      padding: sides,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: _buildInfo(
              colorScheme,
              EdgeInsets.only(top: top, bottom: bottom),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: top, bottom: bottom),
              child: controls,
            ),
          ),
        ],
      ),
    );
  }

  // As the title bar's: the controls stand 14 in from the sides over a fade
  // 16 tall, and 20 above the bottom.
  static const double _glassControlsSide = 14;
  static const double _glassControlsBottom = 20;
  static const double _glassFade = 16;

  Widget _buildGlassControls(ColorScheme colorScheme) {
    return AudioGlassControls(
      position: _buildPosition(),
      progress: _buildProgressBar(colorScheme, volume: false),
      duration: _buildTotal(),
      trailing: _showVolume ? VolumeButton(controller: _controller) : null,
      playModeIcon: Obx(() => Icon(_controller.playMode.value.icon)),
      onPlayMode: _showPlaySettings,
      onPrevious: _controller.playPrev,
      playPause: _controller.animController,
      onPlayPause: _controller.playOrPause,
      onNext: _controller.playNext,
      onPlaylist: _showPlaylist,
    );
  }

  void _showPlaylist() {
    if (_controller.playlist case final playlist?) {
      final initialScrollOffset = 45.0 * _controller.index!;
      final scrollController = ScrollController(
        initialScrollOffset: initialScrollOffset,
      );
      showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxWidth: min(640, context.mediaQueryShortestSide),
        ),
        builder: (context) {
          final colorScheme = ColorScheme.of(context);
          Widget child = CustomScrollView(
            controller: scrollController,
            physics: _controller.reachStart
                ? null
                : const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 100,
                ),
                sliver: SliverList.builder(
                  itemCount: playlist.length,
                  itemBuilder: (_, index) {
                    if (index == playlist.length - 1) {
                      _controller.loadNext(context);
                    }
                    final isCurr = index == _controller.index;
                    final item = playlist[index];
                    if (item.parts.length > 1) {
                      final subId = _controller.subId.firstOrNull;
                      return ExpansionTile(
                        dense: true,
                        minTileHeight: 45,
                        initiallyExpanded: isCurr,
                        collapsedIconColor: isCurr ? colorScheme.primary : null,
                        iconColor: isCurr ? null : colorScheme.onSurfaceVariant,
                        title: Text(
                          item.arc.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isCurr
                              ? TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                )
                              : const TextStyle(fontSize: 14),
                        ),
                        trailing: isCurr
                            ? null
                            : iconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  if (index < _controller.index!) {
                                    _controller.index -= 1;
                                  }
                                  playlist.removeAt(index);
                                  _controller.onPlaylistChanged();
                                  (context as Element).markNeedsBuild();
                                },
                                iconColor: colorScheme.outline,
                                size: 28,
                                iconSize: 18,
                              ),
                        children: item.parts.map((e) {
                          final isCurr = e.subId == subId;
                          return ListTile(
                            dense: true,
                            minTileHeight: 45,
                            contentPadding: const EdgeInsetsDirectional.only(
                              start: 56.0,
                              end: 24.0,
                            ),
                            onTap: () {
                              Get.back();
                              if (!isCurr) {
                                _controller.playIndex(
                                  index,
                                  subId: [e.subId],
                                );
                              }
                            },
                            title: Text.rich(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: isCurr
                                  ? TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    )
                                  : TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              TextSpan(
                                children: [
                                  if (isCurr) ...[
                                    WidgetSpan(
                                      alignment: .bottom,
                                      child: Image.asset(
                                        Assets.livingChart,
                                        width: 16,
                                        height: 16,
                                        cacheWidth: 16.cacheSize(
                                          context,
                                        ),
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const TextSpan(text: '  '),
                                  ],
                                  TextSpan(text: e.title),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }
                    return ListTile(
                      dense: true,
                      minTileHeight: 45,
                      onTap: () {
                        Get.back();
                        if (!isCurr) {
                          _controller.playIndex(index);
                        }
                      },
                      title: Text.rich(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isCurr
                            ? TextStyle(
                                fontSize: 14,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : const TextStyle(fontSize: 14),
                        TextSpan(
                          children: [
                            if (isCurr) ...[
                              WidgetSpan(
                                alignment: .bottom,
                                child: Image.asset(
                                  Assets.livingChart,
                                  width: 16,
                                  height: 16,
                                  cacheWidth: 16.cacheSize(
                                    context,
                                  ),
                                  color: colorScheme.primary,
                                ),
                              ),
                              const TextSpan(text: '  '),
                            ],
                            TextSpan(
                              text: item.arc.title,
                            ),
                          ],
                        ),
                      ),
                      trailing: isCurr
                          ? null
                          : iconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                if (index < _controller.index!) {
                                  _controller.index -= 1;
                                }
                                playlist.removeAt(index);
                                _controller.onPlaylistChanged();
                                (context as Element).markNeedsBuild();
                              },
                              iconColor: colorScheme.outline,
                              size: 28,
                              iconSize: 18,
                            ),
                    );
                  },
                ),
              ),
            ],
          );
          if (!_controller.reachStart) {
            child = refreshIndicator(
              onRefresh: () => _controller.loadPrev(context),
              isClampingScrollPhysics: true,
              child: child,
            );
          }
          return FractionallySizedBox(
            heightFactor:
                PlatformUtils.isMobile && !context.mediaQuerySize.isPortrait
                ? 1.0
                : 0.7,
            alignment: Alignment.bottomCenter,
            child: Column(
              children: [
                InkWell(
                  onTap: Get.back,
                  borderRadius: Style.bottomSheetRadius,
                  child: SizedBox(
                    height: 35,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 3,
                        decoration: BoxDecoration(
                          color: colorScheme.outline,
                          borderRadius: const .all(.circular(3)),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    type: .transparency,
                    child: child,
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outline.withValues(alpha: 0.1),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: InkWell(
                    onTap: Get.back,
                    child: SizedBox(
                      height: 45,
                      child: Center(
                        child: Text(
                          '关闭',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ).whenComplete(scrollController.dispose);
    }
  }

  void _showPlaySettings() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(640, context.mediaQueryShortestSide),
      ),
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: Get.back,
              borderRadius: Style.bottomSheetRadius,
              child: SizedBox(
                height: 35,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 3,
                    decoration: BoxDecoration(
                      color: colorScheme.outline,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                top: 12,
                left: 20,
                right: 20,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 20,
              ),
              child: Column(
                spacing: 12,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) => Column(
                      spacing: 12,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('播放倍速(${_controller.speed})'),
                        Slider(
                          padding: EdgeInsets.zero,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          value: _controller.speed,
                          onChanged: (value) {
                            _controller.speed = value.toPrecision(1);
                            (context as Element).markNeedsBuild();
                          },
                          onChangeEnd: (_) =>
                              _controller.setSpeed(_controller.speed),
                        ),
                      ],
                    ),
                  ),
                  const Text('播放模式'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: PlayRepeat.values
                        .take(4)
                        .map(
                          (e) => _playModeWidget(
                            colorScheme: colorScheme,
                            playMode: e,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _playModeWidget({
    required ColorScheme colorScheme,
    required PlayRepeat playMode,
  }) {
    final isCurr = playMode == _controller.playMode.value;
    final color = isCurr ? colorScheme.primary : colorScheme.outline;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Get.back();
        if (!isCurr) {
          _controller.playMode.value = playMode;
          GStorage.setting.put(SettingBoxKey.audioPlayMode, playMode.index);
        }
      },
      child: Column(
        spacing: 6,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurr
                  ? colorScheme.primary.withValues(alpha: 0.15)
                  : colorScheme.onInverseSurface.withValues(alpha: 0.8),
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                size: 26,
                playMode.icon,
                color: color,
              ),
            ),
          ),
          Text(
            playMode.label,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<void>> _moreEntries(DetailItem? audioItem) {
    final player = _controller.player;
    return [
      if (audioItem != null && audioItem.hasMv)
        menuRow(
          '看MV',
          icon: Icons.play_circle_outline,
          onTap: () {
            // The MV of the track playing now, as 举报 reports that one: the
            // track may have moved on while the menu was open.
            final item = _controller.audioItem.value;
            if (item == null || !item.hasMv) return;
            _controller.onPause();
            PageUtils.toVideoPage(
              cid: item.associatedItem.subId.first.toInt(),
              aid: item.associatedItem.oid.toInt(),
            );
          },
        ),
      if (player != null) ...[
        menuRow(
          '播放信息',
          icon: Icons.info_outline,
          onTap: () =>
              HeaderControlState.showPlayerInfo(context, player: player),
        ),
        if (PlatformUtils.isMobile)
          menuRow(
            '播放器音量: ${player.getProperty('volume').subLength(3)}%',
            icon: Icons.volume_up,
            showKind: false,
            onTap: () => showPlayerVolumeDialog(
              context,
              () {},
              onChanged: _controller.setPlayerVolume,
            ),
          ),
      ],
      if (_controller.isUgc) ...[
        if (player != null || (audioItem?.hasMv ?? false))
          const PopupMenuDivider(),
        menuRow(
          '举报',
          icon: Icons.warning_amber_rounded,
          destructive: true,
          onTap: () => PageUtils.reportVideo(_controller.oid.toInt()),
        ),
      ],
    ];
  }

  void _onDragStart(ThumbDragDetails details) {
    _controller
      ..position.value = details.seconds
      ..isDragging = true;
  }

  void _onDragUpdate(ThumbDragDetails details) {
    _controller.position.value = details.seconds;
  }

  void _onSeek(int milliseconds) {
    _controller
      ..isDragging = false
      ..onSeek(Duration(milliseconds: milliseconds));
  }

  bool get _showVolume => kDebugMode || PlatformUtils.isDesktop;

  Widget _buildProgressBar(ColorScheme colorScheme, {bool volume = true}) {
    final primary = colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final baseBarColor = colorScheme.isDark
        ? const Color(0x33FFFFFF)
        : const Color(0x33999999);
    Widget child = Obx(
      () => ProgressBar(
        progress: _controller.position.value,
        total: _controller.duration.value,
        baseBarColor: baseBarColor,
        progressBarColor: primary,
        bufferedBarColor: Colors.transparent,
        thumbColor: primary,
        thumbGlowColor: thumbGlowColor,
        thumbGlowRadius: 0,
        thumbRadius: 6,
        onDragStart: _onDragStart,
        onDragUpdate: _onDragUpdate,
        onSeek: _onSeek,
      ),
    );
    if (_controller.isUgc && _controller.enableSponsorBlock) {
      child = Stack(
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 3.5,
            child: Obx(
              () {
                if (_controller.segmentProgressList.isNotEmpty) {
                  return SegmentProgressBar(
                    height: 5,
                    segments: _controller.segmentProgressList,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      );
    }
    if (volume && _showVolume) {
      child = Row(
        spacing: 10,
        children: [
          Expanded(child: child),
          VolumeButton(controller: _controller),
        ],
      );
    }
    return child;
  }

  Widget _buildDuration(ColorScheme colorScheme) {
    return SizedBox(
      height: 30,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 13, color: colorScheme.outline),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_buildPosition(), _buildTotal()],
        ),
      ),
    );
  }

  Widget _buildPosition() {
    return Obx(() {
      final position = _controller.position.value;
      if (_controller.player != null) {
        return Text(
          DurationUtils.formatDuration(position),
        );
      }
      return const SizedBox.shrink();
    });
  }

  Widget _buildTotal() {
    return Obx(() {
      final duration = _controller.duration.value;
      if (_controller.player != null) {
        return Text(
          DurationUtils.formatDuration(duration),
        );
      }
      return const SizedBox.shrink();
    });
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Obx(
          () => IconButton(
            onPressed: _showPlaySettings,
            icon: Icon(
              size: 26,
              _controller.playMode.value.icon,
            ),
          ),
        ),
        IconButton(
          onPressed: _controller.playPrev,
          icon: const Icon(
            size: 40,
            Icons.skip_previous_rounded,
          ),
        ),
        IconButton(
          onPressed: _controller.playOrPause,
          icon: AnimatedIcon(
            size: 40,
            icon: AnimatedIcons.play_pause,
            progress: _controller.animController,
          ),
        ),
        IconButton(
          onPressed: _controller.playNext,
          icon: const Icon(
            size: 40,
            Icons.skip_next_rounded,
          ),
        ),
        IconButton(
          onPressed: _showPlaylist,
          icon: const Icon(
            size: 26,
            Icons.menu_rounded,
          ),
        ),
      ],
    );
  }

  /// The cover, title and the rest; its list keeps [padding] clear, the
  /// room the glass bars over it leave.
  Widget _buildInfo(ColorScheme colorScheme, EdgeInsets padding) {
    return Obx(() {
      final audioItem = _controller.audioItem.value;
      if (audioItem != null) {
        final cover = audioItem.arc.cover.http2https;
        return Column(
          children: [
            Expanded(
              child: Center(
                child: ListView(
                  padding: padding,
                  shrinkWrap: true,
                  physics: platformClampingPhysics,
                  key: const PageStorageKey(_AudioPageState),
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: () => PageUtils.imageView(
                          imgList: [SourceModel(url: cover)],
                        ),
                        child: fromHero(
                          tag: cover,
                          child: NetworkImgLayer(
                            src: cover,
                            width: 170,
                            height: 170,
                            cacheWidth: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectionText(
                      audioItem.arc.title,
                      style: const TextStyle(height: 1.7, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    if (audioItem.owner.hasName()) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _controller.onPause();
                          Get.toNamed('/member?mid=${audioItem.owner.mid}');
                        },
                        child: Row(
                          spacing: 6,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (audioItem.owner.hasAvatar())
                              NetworkImgLayer(
                                src: audioItem.owner.avatar,
                                width: 22,
                                height: 22,
                                type: ImageType.avatar,
                              ),
                            Text(
                              audioItem.owner.name,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Icon(
                          size: 14,
                          Icons.headphones_outlined,
                          color: colorScheme.outline,
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    ' ${NumUtils.numFormat(audioItem.stat.view)}   '
                                    '${DateFormatUtils.dateFormat(audioItem.arc.publish.toInt(), long: DateFormatUtils.longFormatD)}   ',
                              ),
                              TextSpan(
                                text: audioItem.arc.displayedOid,
                                style: TextStyle(color: colorScheme.secondary),
                                recognizer: NoDeadlineTapGestureRecognizer()
                                  ..onTap = () => Utils.copyText(
                                    audioItem.arc.displayedOid,
                                  ),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    if (audioItem.arc.hasDesc()) ...[
                      const SizedBox(height: 10),
                      SelectionText(audioItem.arc.desc),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    });
  }
}

extension on DetailItem {
  /// Whether it has a video to watch, its MV.
  bool get hasMv => associatedItem.hasOid() && associatedItem.subId.isNotEmpty;
}

extension _PlayReatExt on PlayRepeat {
  IconData get icon => switch (this) {
    PlayRepeat.pause => Icons.pause_rounded,
    PlayRepeat.listOrder => Icons.keyboard_double_arrow_right_rounded,
    PlayRepeat.singleCycle => Icons.play_circle_outline_rounded,
    PlayRepeat.listCycle => Icons.sync_rounded,
    PlayRepeat.autoPlayRelated => throw UnimplementedError(),
  };
}
