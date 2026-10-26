import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class RadioWidget<T> extends StatefulWidget {
  final T value;
  final String title;
  final bool tristate;
  final EdgeInsetsGeometry? padding;
  final MainAxisSize mainAxisSize;

  const RadioWidget({
    super.key,
    required this.value,
    required this.title,
    this.tristate = false,
    this.padding,
    this.mainAxisSize = MainAxisSize.min,
  });

  @override
  State<RadioWidget<T>> createState() => RadioWidgetState<T>();
}

class RadioWidgetState<T> extends State<RadioWidget<T>> with RadioClient<T> {
  late final _RadioRegistry<T> _radioRegistry = _RadioRegistry<T>(this);

  @override
  final focusNode = FocusNode();

  @override
  T get radioValue => widget.value;

  bool get checked => radioValue == registry!.groupValue;

  @override
  bool get tristate => widget.tristate;

  @override
  bool get enabled => registry != null;

  @override
  void dispose() {
    registry = null;
    focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registry = RadioGroup.maybeOf(context);
    assert(registry != null);
  }

  void _handleTap() {
    if (checked) {
      if (tristate) registry!.onChanged(null);
      return;
    }
    registry!.onChanged(radioValue);
  }

  @override
  Widget build(BuildContext context) {
    // On glass, as an iOS list of choices: a row a choice, pressed on a
    // platter, the chosen one checked at its end.
    // The row reads as a radio button, as the Radio it replaces does.
    if (GlassSurfaces.installed) {
      return MergeSemantics(
        child: Semantics(
          checked: checked,
          inMutuallyExclusiveGroup: true,
          child: InkWell(
            onTap: _handleTap,
            focusNode: focusNode,
            customBorder: const RoundedSuperellipseBorder(
              borderRadius: .all(.circular(12)),
            ),
            child: Padding(
              padding: const .symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title)),
                  if (checked)
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: ColorScheme.of(context).primary,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final child = Row(
      mainAxisSize: widget.mainAxisSize,
      children: [
        ExcludeFocus(
          child: Radio<T>(
            value: radioValue,
            groupRegistry: _radioRegistry,
            materialTapTargetSize: PlatformUtils.isDesktop
                ? .padded
                : .shrinkWrap,
          ),
        ),
        Text(widget.title),
      ],
    );
    return InkWell(
      onTap: _handleTap,
      focusNode: focusNode,
      child: widget.padding == null
          ? child
          : Padding(padding: widget.padding!, child: child),
    );
  }
}

class WrapRadioOptionsGroup<T> extends StatelessWidget {
  final String groupTitle;
  final Map<T, String> options;
  final EdgeInsetsGeometry? itemPadding;

  const WrapRadioOptionsGroup({
    super.key,
    required this.groupTitle,
    required this.options,
    this.itemPadding,
  });

  @override
  Widget build(BuildContext context) {
    // On glass, a section of rows under a footnote title, as an iOS list.
    if (GlassSurfaces.installed) {
      return Padding(
        padding: const .symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (groupTitle.isNotEmpty)
              Padding(
                padding: const .fromLTRB(12, 8, 12, 2),
                child: Text(
                  groupTitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: ColorScheme.of(context).onSurfaceVariant,
                  ),
                ),
              ),
            for (final entry in options.entries)
              RadioWidget<T>(value: entry.key, title: entry.value),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groupTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              groupTitle,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            children: options.entries.map((entry) {
              return RadioWidget<T>(
                value: entry.key,
                title: entry.value,
                padding: itemPadding ?? const EdgeInsets.only(right: 10),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// A registry to controls internal [Radio] and hides it from [RadioGroup]
/// ancestor.
///
/// [RadioListTile] implements the [RadioClient] directly to register to
/// [RadioGroup] ancestor. Therefore, it has to hide the internal [Radio] from
/// participate in the [RadioGroup] ancestor.
class _RadioRegistry<T> extends RadioGroupRegistry<T> {
  _RadioRegistry(this.state);

  final RadioWidgetState<T> state;

  @override
  T? get groupValue => state.registry!.groupValue;

  @override
  ValueChanged<T?> get onChanged => state.registry!.onChanged;

  @override
  void registerClient(RadioClient<T> radio) {}

  @override
  void unregisterClient(RadioClient<T> radio) {}
}
