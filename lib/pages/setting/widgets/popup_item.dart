import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

typedef PopupMenuItemSelected<T> = void Function(
  T value,
  VoidCallback setState,
);

List<PopupMenuEntry<T>> enumItemBuilder<T extends EnumWithLabel>(
  Iterable<T> items,
) => items.map((e) => PopupMenuItem(value: e, child: Text(e.label))).toList();

enum DescPosType { subtitle, title, trailing }

class PopupListTile<T> extends StatefulWidget {
  const PopupListTile({
    super.key,
    this.dense,
    this.safeArea = true,
    this.enabled = true,
    this.leading,
    required this.title,
    this.descPosType = .subtitle,
    required this.value,
    required this.itemBuilder,
    required this.onSelected,
    this.titleStyle,
    this.descStyle,
  });

  final bool? dense;
  final bool safeArea;
  final bool enabled;
  final Widget? leading;
  final Widget title;

  final DescPosType descPosType;
  final ValueGetter<(T, String)> value;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final TextStyle? titleStyle;
  final TextStyle? descStyle;

  @override
  State<PopupListTile<T>> createState() => _PopupListTileState<T>();
}

class _PopupListTileState<T> extends State<PopupListTile<T>> {
  // With liquid glass, as FlClash's option rows: the value sits at the row's
  // end, and the menu opens out of it.
  static final bool _pullDown = Pref.liquidGlass;

  final _key = PlatformUtils.isDesktop ? null : GlobalKey();
  late final _valueKey = GlobalKey<GlassMenuSourceState>();

  void _showPullDown(T value) {
    final source = _valueKey.currentState!;
    final valueBox = source.context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    source.arm();
    _showMenu(
      RelativeRect.fromRect(
        valueBox.localToGlobal(.zero, ancestor: overlay) & valueBox.size,
        Offset.zero & overlay.size,
      ),
      value,
      source: source,
    );
  }

  void _showButtonMenu(TapUpDetails details, T value) {
    final thisOffset = details.globalPosition - details.localPosition;
    final double dx;
    if (PlatformUtils.isDesktop) {
      dx = details.globalPosition.dx + 1;
    } else {
      final thisBox = context.findRenderObject();
      final titleBox = _key!.currentContext!.findRenderObject() as RenderBox;
      final titleOffset = titleBox.localToGlobal(.zero, ancestor: thisBox);
      dx = thisOffset.dx + titleOffset.dx;
    }
    _showMenu(RelativeRect.fromLTRB(dx, thisOffset.dy + 5, dx, 0), value);
  }

  void _showMenu(
    RelativeRect position,
    T value, {
    GlassMenuSourceState? source,
  }) {
    showMenu<T>(
      context: context,
      position: position,
      items: widget.itemBuilder(context),
      initialValue: value,
      requestFocus: false,
    ).then<void>((newValue) async {
      if (!mounted) return;
      if (newValue == null || newValue == value) return;
      // The menu returns into the value as it was, which then changes in
      // place.
      await source?.landed;
      if (!mounted) return;
      widget.onSelected(newValue, _refresh);
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (value, descStr) = widget.value();
    Widget title = KeyedSubtree(key: _key, child: widget.title);
    Widget? subtitle;
    Widget? trailing;
    if (_pullDown) {
      final color = widget.enabled
          ? theme.colorScheme.onSurfaceVariant
          : theme.disabledColor;
      return ListTile(
        dense: widget.dense,
        safeArea: widget.safeArea,
        enabled: widget.enabled,
        onTap: () => _showPullDown(value),
        leading: widget.leading,
        title: widget.title,
        titleTextStyle: widget.titleStyle ?? theme.textTheme.titleMedium,
        trailing: GlassMenuSource(
          key: _valueKey,
          child: Row(
            mainAxisSize: .min,
            spacing: 4,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  descStr,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodyMedium!.copyWith(color: color),
                ),
              ),
              Icon(Icons.unfold_more_rounded, size: 18, color: color),
            ],
          ),
        ),
      );
    }
    final desc = Text(
      descStr,
      style: (widget.descStyle ?? theme.textTheme.labelMedium!).copyWith(
        color: widget.enabled
            ? theme.colorScheme.secondary
            : theme.disabledColor,
      ),
    );
    switch (widget.descPosType) {
      case DescPosType.subtitle:
        subtitle = desc;
      case DescPosType.title:
        title = Row(
          spacing: 12,
          mainAxisSize: .min,
          children: [title, desc],
        );
      case DescPosType.trailing:
        trailing = desc;
    }
    return ListTile(
      dense: widget.dense,
      safeArea: widget.safeArea,
      enabled: widget.enabled,
      onTapUp: (details) => _showButtonMenu(details, value),
      leading: widget.leading,
      title: title,
      titleTextStyle: widget.titleStyle ?? theme.textTheme.titleMedium,
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}
