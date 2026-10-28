import 'package:PiliPlus/common/widgets/flutter/chat_list_view.dart';
import 'package:PiliPlus/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart'
    show
        BoxHitTestResult,
        ChildLayoutHelper,
        PipelineOwner,
        RenderSliverEdgeInsetsPadding;
import 'package:material_ui/material_ui.dart';

/// How far the bar laid over the end of a chat covers it. [GlassChatLayout]
/// sets it as it lays the bar out, and the [InsetChatListView] it holds keeps
/// its newest message clear of the bar in that same frame, so the messages
/// move with the bar as the keyboard brings it up or takes it down.
///
/// Only render objects listen to it: it changes during layout.
class ChatBarInset extends ChangeNotifier {
  double get value => _value;
  double _value = 0;

  void _set(double value) {
    _value = value;
    notifyListeners();
  }
}

enum GlassChatSlot { bar, messages }

/// Lays [bar] over the bottom of [messages], which fill the space and scroll
/// under it, and tells [inset] how tall it is. [bar] spans the width; only
/// what in it takes a touch keeps it from the messages.
class GlassChatLayout
    extends SlottedMultiChildRenderObjectWidget<GlassChatSlot, RenderBox> {
  const GlassChatLayout({
    super.key,
    required this.inset,
    required this.messages,
    required this.bar,
  });

  final ChatBarInset inset;
  final Widget messages;
  final Widget bar;

  @override
  Iterable<GlassChatSlot> get slots => GlassChatSlot.values;

  @override
  Widget? childForSlot(GlassChatSlot slot) => switch (slot) {
    .bar => bar,
    .messages => messages,
  };

  @override
  RenderGlassChatLayout createRenderObject(BuildContext context) =>
      RenderGlassChatLayout(inset);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassChatLayout renderObject,
  ) {
    renderObject.inset = inset;
  }
}

class RenderGlassChatLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<GlassChatSlot, RenderBox> {
  RenderGlassChatLayout(this._inset);

  ChatBarInset _inset;
  set inset(ChatBarInset value) {
    if (_inset == value) return;
    _inset = value;
    markNeedsLayout();
  }

  RenderBox get _bar => childForSlot(.bar)!;
  RenderBox get _messages => childForSlot(.messages)!;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final barHeight = ChildLayoutHelper.layoutChild(
      _bar,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    ).height;
    setOffset(_bar, Offset(0, size.height - barHeight));
    if (_inset.value != barHeight) {
      // Lays the list out again with room for the bar before it paints.
      invokeLayoutCallback<BoxConstraints>((_) => _inset._set(barHeight));
    }
    _messages.layout(BoxConstraints.tight(size));
    setOffset(_messages, .zero);
  }

  // The bar first, as it lies on top. Where nothing of it takes the touch,
  // beside or between its panes, the messages under it do.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_bar, _messages]) {
      final isHit = result.addWithPaintOffset(
        offset: getOffset(child),
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (isHit) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context
      ..paintChild(_messages, getOffset(_messages) + offset)
      ..paintChild(_bar, getOffset(_bar) + offset);
  }
}

/// A [ChatListView] whose newest message, at its end, keeps clear of the bar
/// laid over it by [inset], while older ones scroll on under the bar.
class InsetChatListView extends ChatListView {
  InsetChatListView.separated({
    super.key,
    required this.inset,
    required super.maxExtent,
    super.controller,
    super.physics,
    super.padding,
    required super.itemBuilder,
    required super.separatorBuilder,
    required super.itemCount,
  }) : super.separated();

  final ChatBarInset inset;

  @override
  Widget buildChildLayout(BuildContext context) => _SliverChatBarInset(
    inset: inset,
    sliver: super.buildChildLayout(context),
  );
}

class _SliverChatBarInset extends SingleChildRenderObjectWidget {
  const _SliverChatBarInset({required this.inset, required Widget sliver})
    : super(child: sliver);

  final ChatBarInset inset;

  @override
  _RenderSliverChatBarInset createRenderObject(BuildContext context) =>
      _RenderSliverChatBarInset(inset);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverChatBarInset renderObject,
  ) {
    renderObject.inset = inset;
  }
}

// Padding at the bottom: a chat's list is reversed, its end at the bottom.
class _RenderSliverChatBarInset extends RenderSliverEdgeInsetsPadding {
  _RenderSliverChatBarInset(this._inset);

  ChatBarInset _inset;
  set inset(ChatBarInset value) {
    if (_inset == value) return;
    if (attached) {
      _inset.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _inset = value;
    markNeedsLayout();
  }

  @override
  EdgeInsets get resolvedPadding => EdgeInsets.only(bottom: _inset.value);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _inset.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _inset.removeListener(markNeedsLayout);
    super.detach();
  }
}
