// After FlClash's alert actions (https://github.com/chen08209/FlClash,
// lib/ui/dialog.dart, GPL-3.0).

import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

const double _actionGap = 8;
const double _actionHeight = 48;
const double _pressedFillShare = 0.4;
const double _pressedDarkDefaultShare = 0.5;

/// An alert's buttons as iOS lays them out: capsules, two side by side when
/// both labels fit half the width, any other count stacked with the cancel
/// action, 取消 or the first, at the bottom. The last one is the default
/// action and is filled, unless its caller colored it, as a destructive one
/// is.
class GlassAlertActions extends StatelessWidget {
  const GlassAlertActions({super.key, required this.actions});

  final List<Widget> actions;

  // A caller's own color, as a destructive action's; the outline color it
  // mutes a cancel action in doesn't count.
  static bool _colored(Widget action, ColorScheme colorScheme) =>
      switch (action) {
        ButtonStyleButton(:final style?) when style.foregroundColor != null =>
          true,
        ButtonStyleButton(child: Text(:final style?))
            when style.color != null && style.color != colorScheme.outline =>
          true,
        _ => false,
      };

  static bool _isCancel(Widget action, ColorScheme colorScheme) =>
      switch (action) {
        ButtonStyleButton(child: Text(:final data)) when data == '取消' => true,
        ButtonStyleButton(child: Text(:final style?))
            when style.color == colorScheme.outline =>
          true,
        _ => false,
      };

  // On a capsule the outline color reads as disabled: a muted cancel action
  // takes the capsule's own color.
  static Widget _unmuted(Widget action, ColorScheme colorScheme) =>
      switch (action) {
        TextButton(
          :final key,
          :final onPressed,
          :final onLongPress,
          :final style,
          child: Text(:final data?, style: final textStyle?),
        )
            when textStyle.color == colorScheme.outline =>
          TextButton(
            key: key,
            onPressed: onPressed,
            onLongPress: onLongPress,
            style: style,
            child: Text(
              data,
              style: TextStyle(
                fontSize: textStyle.fontSize,
                fontWeight: textStyle.fontWeight,
              ),
            ),
          ),
        _ => action,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    // The cancel action ends a stack, or starts a pair, wherever the caller
    // put it.
    final cancel = actions.indexWhere(
      (action) => _isCancel(action, colorScheme),
    );
    final ordered = cancel <= 0
        ? actions
        : [
            actions[cancel],
            ...actions.take(cancel),
            ...actions.skip(cancel + 1),
          ];
    return _AlertActions(
      children: [
        for (final (index, action) in ordered.indexed)
          _AlertAction(
            isDefault:
                index == ordered.length - 1 &&
                !(index == 0 && cancel >= 0) &&
                !_colored(action, colorScheme),
            child: _unmuted(action, colorScheme),
          ),
      ],
    );
  }
}

class _AlertAction extends StatelessWidget {
  const _AlertAction({required this.isDefault, required this.child});

  final bool isDefault;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final fill = glassFillOf(colorScheme);
    final foreground = isDefault
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final background = isDefault ? colorScheme.primary : fill;
    final pressedShare = switch ((isDefault, dark)) {
      (true, true) => _pressedDarkDefaultShare,
      (false, true) => 1.0,
      _ => _pressedFillShare,
    };
    final body = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 17,
      height: 22 / 17,
      letterSpacing: 0,
      fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
    );
    return TextButtonTheme(
      data: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: colorScheme.onSurface.withValues(
                alpha: 0.38,
              ),
              textStyle: body,
              minimumSize: const Size(0, _actionHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
            ).copyWith(
              backgroundColor: WidgetStateProperty<Color?>.fromMap({
                WidgetState.disabled: fill,
                WidgetState.pressed: background.withValues(
                  alpha: background.a * pressedShare,
                ),
                WidgetState.any: background,
              }),
              overlayColor: WidgetStateProperty<Color?>.fromMap({
                WidgetState.focused: foreground.withValues(alpha: 0.1),
                WidgetState.pressed: Colors.transparent,
                WidgetState.hovered: foreground.withValues(alpha: 0.08),
              }),
            ),
      ),
      child: child,
    );
  }
}

class _AlertActions extends MultiChildRenderObjectWidget {
  const _AlertActions({required super.children});

  @override
  _RenderAlertActions createRenderObject(BuildContext context) =>
      _RenderAlertActions(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertActions renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _AlertActionsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAlertActions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AlertActionsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AlertActionsParentData> {
  _RenderAlertActions(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AlertActionsParentData) {
      child.parentData = _AlertActionsParentData();
    }
  }

  bool _sideBySide(List<RenderBox> children, double width) =>
      children.length == 2 &&
      children.every(
        (child) =>
            child.getMaxIntrinsicWidth(double.infinity) <=
            (width - _actionGap) / 2,
      );

  double _childWidth(bool sideBySide, double width) =>
      sideBySide ? (width - _actionGap) / 2 : width;

  double _widest(double Function(RenderBox child) widthOf) =>
      getChildrenAsList().map(widthOf).fold(0, math.max);

  double _heightFor(
    double width,
    double Function(RenderBox child, double width) heightOf,
  ) {
    final children = getChildrenAsList();
    if (children.isEmpty) {
      return 0;
    }
    final sideBySide = _sideBySide(children, width);
    final heights = children.map(
      (child) => heightOf(child, _childWidth(sideBySide, width)),
    );
    return sideBySide
        ? heights.reduce(math.max)
        : heights.reduce((a, b) => a + b) + _actionGap * (children.length - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widest((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widest((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _heightFor(width, (child, width) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _heightFor(width, (child, width) => child.getMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    bool place = false,
  }) {
    final children = getChildrenAsList();
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _widest((child) => child.getMaxIntrinsicWidth(double.infinity));
    final sideBySide = _sideBySide(children, width);
    final childConstraints = BoxConstraints.tightFor(
      width: _childWidth(sideBySide, width),
    );
    final sizes = [
      for (final child in children) layoutChild(child, childConstraints),
    ];
    final height = sizes.isEmpty
        ? 0.0
        : sideBySide
        ? math.max(sizes.first.height, sizes.last.height)
        : sizes.fold(0.0, (sum, size) => sum + size.height) +
              _actionGap * (sizes.length - 1);
    if (place) {
      final rtl = _textDirection == TextDirection.rtl;
      var y = 0.0;
      // From the second down, so that the first ends a stack.
      for (var step = 1; step <= children.length; step++) {
        final index = step % children.length;
        final size = sizes[index];
        final parentData =
            children[index].parentData! as _AlertActionsParentData;
        if (sideBySide) {
          final atLeft = (index == 0) != rtl;
          parentData.offset = Offset(
            atLeft ? 0 : width - size.width,
            (height - size.height) / 2,
          );
        } else {
          parentData.offset = Offset(0, y);
          y += size.height + _actionGap;
        }
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
