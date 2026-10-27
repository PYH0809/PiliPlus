import 'package:material_ui/material_ui.dart';

/// Opens a popup menu out of [button], the context of the control that opens
/// it, so that the menu grows from it.
Future<T?> showMenuFrom<T>(
  BuildContext button,
  List<PopupMenuEntry<T>> items,
) {
  final box = button.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(button).overlay!.context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: button,
    position: RelativeRect.fromRect(
      box.localToGlobal(.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// A section's title in a popup menu, as an iOS menu's: footnote text in the
/// secondary color, with an optional second line, and not pressable.
class MenuSectionHeader extends PopupMenuEntry<Never> {
  const MenuSectionHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  double get height => subtitle == null ? 30 : 48;

  @override
  bool represents(void value) => false;

  @override
  State<MenuSectionHeader> createState() => _MenuSectionHeaderState();
}

class _MenuSectionHeaderState extends State<MenuSectionHeader> {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      height: 18 / 13,
      color: ColorScheme.of(context).onSurfaceVariant,
    );
    return Semantics(
      header: true,
      child: Padding(
        padding: const .fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(widget.title, style: style.copyWith(fontWeight: .w600)),
            if (widget.subtitle case final subtitle?)
              Text(subtitle, style: style),
          ],
        ),
      ),
    );
  }
}

// What the API calls a reason such as "UP主:name": its kind, then the name.
final _kindAndName = RegExp(r'^([^:：]{1,6})[:：]\s*(.+)$');

/// The icon for a reason not to recommend something, by its kind.
IconData reasonIcon(String name) =>
    switch (_kindAndName.firstMatch(name)?.group(1)) {
      'UP主' => Icons.person_outline,
      '分区' => Icons.category_outlined,
      '频道' => Icons.tag,
      _ => Icons.thumb_down_outlined,
    };

/// A row of a popup menu with an optional [icon]. A [name] such as "UP主:name"
/// shows its kind in the secondary color before the name, unless [showKind] is
/// off, as for an action such as "临时屏蔽：name". A [destructive] row, such as
/// 删除, is in the error color.
PopupMenuItem<T> menuRow<T>(
  String name, {
  IconData? icon,
  T? value,
  VoidCallback? onTap,
  bool showKind = true,
  bool destructive = false,
}) => PopupMenuItem<T>(
  value: value,
  onTap: onTap,
  child: _MenuRow(
    name,
    icon,
    showKind: showKind,
    destructive: destructive,
  ),
);

class _MenuRow extends StatelessWidget {
  const _MenuRow(
    this.name,
    this.icon, {
    required this.showKind,
    required this.destructive,
  });

  final String name;
  final IconData? icon;
  final bool showKind;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final match = showKind ? _kindAndName.firstMatch(name) : null;
    final color = destructive ? ColorScheme.of(context).error : null;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Text.rich(
            style: TextStyle(color: color),
            match == null
                ? TextSpan(text: name)
                : TextSpan(
                    children: [
                      TextSpan(
                        text: '${match.group(1)}  ',
                        style: TextStyle(
                          color: ColorScheme.of(context).onSurfaceVariant,
                        ),
                      ),
                      TextSpan(text: match.group(2)),
                    ],
                  ),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ),
      ],
    );
  }
}
