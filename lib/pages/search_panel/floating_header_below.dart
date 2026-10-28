import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';

/// A [SliverFloatingHeaderWidget] for results under a header laid over them,
/// as on glass. It leaves [inset] clear above [child], where the results show
/// through the header, and, floating back, [child] slides out from under the
/// header to just below it.
class SliverFloatingHeaderBelow extends StatelessWidget {
  const SliverFloatingHeaderBelow({
    super.key,
    required this.inset,
    required this.backgroundColor,
    required this.child,
  });

  final double inset;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _FloatingHeaderBelow(
      inset: inset,
      child: _ScrollStart(
        child: Padding(
          padding: EdgeInsets.only(top: inset),
          child: ColoredBox(color: backgroundColor, child: child),
        ),
      ),
    );
  }
}

/// Tells the header which way each scroll starts, as
/// [SliverFloatingHeaderWidget] does its own.
class _ScrollStart extends StatefulWidget {
  const _ScrollStart({required this.child});

  final Widget child;

  @override
  State<_ScrollStart> createState() => _ScrollStartState();
}

class _ScrollStartState extends State<_ScrollStart> {
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.isScrollingNotifier.removeListener(_handleScrolling);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.isScrollingNotifier.addListener(_handleScrolling);
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_handleScrolling);
    super.dispose();
  }

  void _handleScrolling() {
    final position = _position!;
    if (position.isScrollingNotifier.value) {
      context
          .findAncestorRenderObjectOfType<_RenderFloatingHeaderBelow>()
          ?.updateScrollStartDirection(position.userScrollDirection);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FloatingHeaderBelow extends SingleChildRenderObjectWidget {
  const _FloatingHeaderBelow({
    required this.inset,
    required Widget super.child,
  });

  final double inset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFloatingHeaderBelow(inset: inset);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFloatingHeaderBelow renderObject,
  ) {
    renderObject.inset = inset;
  }
}

/// A [RenderSliverFloatingHeader] whose child stands [inset] down in it.
/// Floating back, the child starts just under the header's bottom edge,
/// rather than the whole of it above the viewport's top edge, so that it is
/// out from under the header as soon as it would be out without one. Where
/// it starts, the header hides it.
class _RenderFloatingHeaderBelow extends RenderSliverFloatingHeader {
  _RenderFloatingHeaderBelow({required this.inset})
    : super(backgroundColor: Colors.transparent);

  double inset;

  ScrollDirection? _scrollStartDirection;

  @override
  void updateScrollStartDirection(ScrollDirection direction) {
    super.updateScrollStartDirection(direction);
    _scrollStartDirection = direction;
  }

  @override
  void performLayout() {
    // As the header's own layout decides to float back.
    if (floatingHeaderNeedsToBeUpdated &&
        (constraints.userScrollDirection == .forward ||
            _scrollStartDirection == .forward)) {
      final underHeader = child!.size.height - inset;
      if (effectiveScrollOffset > underHeader) {
        effectiveScrollOffset = underHeader;
      }
    }
    super.performLayout();
  }
}
