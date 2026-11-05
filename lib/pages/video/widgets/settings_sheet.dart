import 'package:PiliPlus/pages/setting/widgets/popup_item.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Where a row of the player's settings sheet goes: on its first level, or
/// in one of the groups it opens.
enum SettingsGroup {
  top('', Icons.tune),
  picture('画面', Icons.tv_outlined),
  sound('声音', Icons.volume_up_outlined),
  danmaku('弹幕和字幕', Icons.subtitles_outlined),
  trouble('播放问题', Icons.build_outlined),
  more('更多', Icons.more_horiz);

  const SettingsGroup(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A row of the settings sheet, marked with the group it goes in and where
/// in it. It builds [child] as it is.
class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    super.key,
    this.group = SettingsGroup.top,
    this.order = 0,
    required this.child,
  });

  final SettingsGroup group;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

// Where the sheet's rows go, by their titles, so that the sheet's own code
// keeps its rows as they are; a row with no title to read, as one built in a
// Builder, says where it goes with a [SettingsEntry]. A row neither names
// goes in 更多.
const _byTitle = <String, (SettingsGroup, int)>{
  '添加至「稍后再看」': (.top, 0),
  '离线缓存': (.top, 1),
  '定时关闭': (.top, 2),
  '播放顺序': (.top, 3),
  '选择画质': (.picture, 0),
  '超分辨率': (.picture, 1),
  '解码格式': (.picture, 2),
  '选择音质': (.sound, 0),
  '弹幕设置': (.danmaku, 0),
  '弹幕列表': (.danmaku, 1),
  '字幕设置': (.danmaku, 2),
  '加载字幕': (.danmaku, 3),
  '保存字幕': (.danmaku, 4),
  '重载视频': (.trouble, 0),
  'CDN 设置': (.trouble, 1),
  '播放地址': (.trouble, 2),
  '播放信息': (.trouble, 3),
  '查看笔记': (.more, 0),
  '保存封面': (.more, 1),
  '举报': (.more, 2),
};

(SettingsGroup, int) _placeOf(Widget row) {
  if (row case SettingsEntry(:final group, :final order)) {
    return (group, order);
  }
  final title = switch (row) {
    ListTile(:final Text title) => title.data,
    PopupListTile(:final Text title) => title.data,
    _ => null,
  };
  return _byTitle[title] ?? (SettingsGroup.more, 9);
}

/// The settings sheet's rows in levels: the first holds those of
/// [SettingsGroup.top], then a row for each group with rows of its own,
/// which opens it in place; its title row goes back, as does the system's
/// back.
class GroupedSettings extends StatefulWidget {
  const GroupedSettings({super.key, required this.children});

  final List<Widget> children;

  @override
  State<GroupedSettings> createState() => _GroupedSettingsState();
}

class _GroupedSettingsState extends State<GroupedSettings>
    with SingleTickerProviderStateMixin {
  // 0, the first level; 1, the group open over it.
  late final _push = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  SettingsGroup? _open;

  // Each level's height as it laid out, to lerp the sheet's between.
  double? _topHeight;
  double? _groupHeight;

  // A drag from the left edge, going back as the finger moves.
  bool _dragging = false;
  static const _edge = 24.0;
  static const _curve = Curves.fastEaseInToSlowEaseOut;

  @override
  void initState() {
    super.initState();
    _push.addStatusListener((status) {
      // Not under a finger still: a drag that reached the edge may yet
      // come back, and lets the group go only once let go of.
      if (status.isDismissed && _open != null && !_dragging) {
        setState(() => _open = null);
      }
    });
  }

  @override
  void dispose() {
    _push.dispose();
    super.dispose();
  }

  void _openGroup(SettingsGroup group) {
    setState(() {
      _open = group;
      _groupHeight = null;
    });
    _go(1);
  }

  void _back() => _go(0);

  // With animations turned off, it jumps.
  void _go(double target) {
    if (target == 0 && _push.value == 0) {
      // There already, as a drag let go of at the edge: nothing moves to
      // say so. A push just set off and yet to move stops here too, or it
      // would carry the first level aside with no group beside it.
      _push.stop();
      if (_open != null) setState(() => _open = null);
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _push.value = target;
    } else if (target == 0) {
      // Back, so that it ends dismissed and lets the group go.
      _push.animateBack(0, curve: _curve);
    } else {
      _push.animateTo(target, curve: _curve);
    }
  }

  List<Widget> _of(SettingsGroup group) {
    // Stable: rows of one order keep the order they were given in.
    final rows =
        [
          for (final (index, row) in widget.children.indexed)
            if (_placeOf(row) case (final at, final order) when at == group)
              (index, order, row),
        ]..sort((a, b) {
          final byOrder = a.$2.compareTo(b.$2);
          return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
        });
    return [for (final (_, _, row) in rows) row];
  }

  // Neither level takes the route's primary scroll controller: both are
  // built at once as a group opens, which one controller cannot serve.
  Widget _topLevel() => ListView(
    primary: false,
    shrinkWrap: true,
    padding: const EdgeInsets.symmetric(vertical: 14),
    children: [
      ..._of(SettingsGroup.top),
      for (final group in SettingsGroup.values.skip(1))
        if (_of(group).isNotEmpty)
          ListTile(
            dense: true,
            leading: Icon(group.icon, size: 20),
            title: Text(group.label, style: const TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => _openGroup(group),
          ),
    ],
  );

  Widget _groupLevel(SettingsGroup group) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        dense: true,
        leading: const Icon(Icons.arrow_back, size: 20),
        title: Text(
          group.label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onTap: _back,
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
      Flexible(
        child: ListView(
          primary: false,
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 6, bottom: 14),
          children: _of(group),
        ),
      ),
    ],
  );

  void _onDragStart(DragStartDetails details) {
    _dragging = _open != null && details.localPosition.dx < _edge;
    if (_dragging) _push.stop();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (!_dragging) return;
    _push.value -= details.primaryDelta! / width;
  }

  // The system took the drag away: the group comes in again.
  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _go(1);
  }

  void _onDragEnd(DragEndDetails details, double width) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    // Past halfway or flung, it goes back; else it comes in again.
    if (velocity > 700 || (velocity > -700 && _push.value < 0.5)) {
      _back();
    } else {
      _go(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Where the finger came down, not where it set off past the
            // slop, tells whether it came from the edge.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: open == null ? null : _onDragStart,
            onHorizontalDragUpdate: open == null
                ? null
                : (details) => _onDragUpdate(details, width),
            onHorizontalDragEnd: open == null
                ? null
                : (details) => _onDragEnd(details, width),
            onHorizontalDragCancel: open == null ? null : _onDragCancel,
            child: AnimatedBuilder(
              animation: _push,
              builder: (context, _) {
                final t = _push.value;
                final from = _topHeight ?? maxHeight;
                final to = open == null ? from : _groupHeight ?? from;
                final height = (from + (to - from) * t).clamp(0.0, maxHeight);
                return SizedBox(
                  height: height.isFinite ? height : null,
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // The first level, slid aside as a group comes over
                        // it, and hidden under it: the group's rows lie on
                        // the same see-through glass.
                        Positioned(
                          left: -width * 0.28 * t,
                          width: width,
                          top: 0,
                          child: _Measured(
                            maxHeight: maxHeight,
                            onHeight: (h) {
                              if (_topHeight != h) {
                                _topHeight = h;
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) {
                                    if (mounted) setState(() {});
                                  },
                                );
                              }
                            },
                            // Under a group, out of reach of taps, the
                            // keyboard's focus and assistive technology.
                            child: IgnorePointer(
                              ignoring: open != null,
                              child: ExcludeFocus(
                                excluding: open != null,
                                child: ExcludeSemantics(
                                  excluding: open != null,
                                  // Cut at the group's leading edge, as an
                                  // opaque page would cover it there: a fade
                                  // drew the level offscreen every frame.
                                  child: ClipRect(
                                    clipper: _LeftOf(
                                      open == null
                                          ? double.infinity
                                          : width * (1 - t) + width * 0.28 * t,
                                    ),
                                    // Its own Material, so that a row's press
                                    // goes with it, cut where it is cut.
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: _topLevel(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (open != null) ...[
                          Positioned(
                            left: width * (1 - t),
                            width: width,
                            top: 0,
                            child: _Measured(
                              maxHeight: maxHeight,
                              onHeight: (h) {
                                if (_groupHeight != h) {
                                  _groupHeight = h;
                                  // The first frame of a group lays it out
                                  // to learn its height.
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) setState(() {});
                                  });
                                }
                              },
                              child: Material(
                                type: MaterialType.transparency,
                                child: _groupLevel(open),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.width);

  final double width;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, width.clamp(0.0, size.width), size.height);

  @override
  bool shouldReclip(_LeftOf oldClipper) => oldClipper.width != width;
}

/// [child] laid out at its own height, up to [maxHeight], which it hands
/// to [onHeight].
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({
    required this.maxHeight,
    required this.onHeight,
    super.child,
  });

  final double maxHeight;
  final ValueChanged<double> onHeight;

  @override
  _RenderMeasured createRenderObject(BuildContext context) =>
      _RenderMeasured(maxHeight, onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject
      ..maxHeight = maxHeight
      ..onHeight = onHeight;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this._maxHeight, this.onHeight);

  double _maxHeight;
  set maxHeight(double value) {
    if (_maxHeight == value) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    child!.layout(
      constraints.copyWith(minHeight: 0, maxHeight: _maxHeight),
      parentUsesSize: true,
    );
    size = constraints.constrain(child!.size);
    onHeight(child!.size.height);
  }
}

/// A row that switches [value], for settings that turn on and off.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Transform.scale(
        scale: 0.8,
        child: Switch(value: value, onChanged: onChanged),
      ),
      onTap: () => onChanged(!value),
    );
  }
}
