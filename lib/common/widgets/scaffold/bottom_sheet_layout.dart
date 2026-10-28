import 'package:PiliPlus/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, ChildLayoutHelper, PipelineOwner;
import 'package:material_ui/material_ui.dart';

enum BottomSheetType { bottomSheet, body }

class BottomSheetLayout
    extends SlottedMultiChildRenderObjectWidget<BottomSheetType, RenderBox> {
  const BottomSheetLayout({
    super.key,
    this.bottomSheet,
    required this.body,
    this.opaqueSheet,
  });

  final Widget? bottomSheet;
  final Widget body;

  /// [bottomSheet] coming up, when it paints all of its area: once it is up
  /// and spans the whole layout, [body] is not painted, as none of it shows.
  final Animation<double>? opaqueSheet;

  @override
  Iterable<BottomSheetType> get slots => BottomSheetType.values;

  @override
  Widget? childForSlot(slot) => switch (slot) {
    .bottomSheet => bottomSheet,
    .body => body,
  };

  @override
  SlottedContainerRenderObjectMixin<BottomSheetType, RenderBox>
  createRenderObject(
    BuildContext context,
  ) {
    return _RenderScaffoldLayout(opaqueSheet: opaqueSheet);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    SlottedContainerRenderObjectMixin<BottomSheetType, RenderBox> renderObject,
  ) {
    (renderObject as _RenderScaffoldLayout).opaqueSheet = opaqueSheet;
  }
}

class _RenderScaffoldLayout extends RenderBox
    with
        SlottedContainerRenderObjectMixin<BottomSheetType, RenderBox>,
        SlottedLayoutMixin {
  _RenderScaffoldLayout({this._opaqueSheet});

  Animation<double>? _opaqueSheet;
  set opaqueSheet(Animation<double>? value) {
    if (_opaqueSheet == value) return;
    if (attached) {
      _opaqueSheet?.removeStatusListener(_onSheetStatus);
      value?.addStatusListener(_onSheetStatus);
    }
    _opaqueSheet = value;
    markNeedsPaint();
  }

  void _onSheetStatus(AnimationStatus status) => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opaqueSheet?.addStatusListener(_onSheetStatus);
  }

  @override
  void detach() {
    _opaqueSheet?.removeStatusListener(_onSheetStatus);
    super.detach();
  }

  RenderBox? get bottomSheet => childForSlot(.bottomSheet);
  RenderBox get body => childForSlot(.body)!;

  @override
  Iterable<BottomSheetType> get slots => BottomSheetType.values;

  @override
  void performLayout() {
    final constraints = this.constraints;
    size = constraints.biggest;

    final childConstraints = constraints.loosen();
    final body = this.body..layout(childConstraints);
    setOffset(body, .zero);

    final bottomSheet = this.bottomSheet;
    if (bottomSheet != null) {
      final size = ChildLayoutHelper.layoutChild(bottomSheet, childConstraints);
      setOffset(bottomSheet, Offset(0, constraints.maxHeight - size.height));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    void doPaint(RenderBox? child) {
      if (child != null) {
        context.paintChild(child, getOffset(child) + offset);
      }
    }

    // Painted under an opaque sheet, the body would still cost the GPU every
    // frame, its glass most of all, which has no cache to draw it from.
    final bottomSheet = this.bottomSheet;
    final covered =
        bottomSheet != null &&
        (_opaqueSheet?.isCompleted ?? false) &&
        bottomSheet.size >= size;
    if (!covered) doPaint(body);
    doPaint(bottomSheet);
  }
}
