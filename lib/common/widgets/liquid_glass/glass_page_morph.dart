// After FlClash's popup morph (https://github.com/chen08209/FlClash,
// lib/ui/popup.dart, GPL-3.0), carried over to pages: a page grows out of
// the glass button that opens it, and returns into it as a drop of glass.

import 'dart:math' as math;
import 'dart:ui' as ui show Image, ImageFilter, lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_button_group.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_droplet.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/goo.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

// As FlClash's popup opens, measured on iOS: one spring, with a little
// overshoot, carries the card out of its button; its corners follow on a
// second a moment later, and it dips as it leaves.
final _open = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 0.754),
  0,
  1,
  0,
);
final _corners = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 324, ratio: 0.75),
  1,
  0,
  0,
);
const _cornersDelay = 0.07;
const _cornersReach = 0.48;
const _rimDepth = 8.0;

// Both springs settle in half a second of their own time, which the route
// plays in less: a little slower than they run as it starts, so the glass
// is seen to swell, and faster through their tail, which hardly moves, so
// the page is live sooner. The route keeps the time, rather than springs of
// its own, so the navigator knows when the page has opened.
const _openDuration = Duration(milliseconds: 360);
const _openSeconds = 0.5;
const _openPace = Cubic(1 / 3, 0.2, 2 / 3, 8 / 15);

// How far into its return the page fades into the glass as it shrinks with
// it, its fill a little behind, and how frosted it is by then.
const _contentOut = Interval(0.3, 0.8, curve: Curves.easeIn);
const _fillOut = Interval(0.4, 0.9, curve: Curves.easeIn);
const _returnFrost = 6.0;

// A blur the page takes below this does not show, so it takes none; nor does
// it take more than this, on the page as drawn, before it is shrunk.
const _blurUnseen = 0.5;
const _blurMost = 64.0;

/// A [LiquidGlassButton] that opens a page out of itself, as FlClash's and
/// iOS's buttons open their popovers: the page grows out of the button's
/// glass, and returns into it as a drop of glass as it closes. [onTap] opens
/// it with [GlassMorphButtonState.toNamed]. While the page is open the button
/// stands hidden, the morph drawing it: [child] is built there too, so it
/// holds no [GlobalKey].
class GlassMorphButton extends StatefulWidget {
  const GlassMorphButton({
    super.key,
    required this.onTap,
    required this.child,
    this.styleOf = LiquidGlassStyle.regular,
    this.shadows = const [],
    this.tooltip,
  });

  final void Function(GlassMorphButtonState button) onTap;
  final Widget child;
  final LiquidGlassStyle Function(ColorScheme colorScheme) styleOf;
  final List<BoxShadow> shadows;
  final String? tooltip;

  @override
  State<GlassMorphButton> createState() => GlassMorphButtonState();

  /// Whether the page [context] is in is still growing out of a glass
  /// button; if so, [then] runs once it has, unless it closes first. A page
  /// holds back what would jank the morph until then, as the search page
  /// does its keyboard: laying the page out under a keyboard rising with it
  /// costs every frame of the morph.
  static bool deferUntilOpened(BuildContext context, VoidCallback then) {
    final animation = switch (ModalRoute.of(context)) {
      final _GlassMorphRoute<dynamic> route => route._own,
      _ => null,
    };
    if (animation == null || animation.status != AnimationStatus.forward) {
      return false;
    }
    void handleStatus(AnimationStatus status) {
      if (status == AnimationStatus.forward) {
        return;
      }
      animation.removeStatusListener(handleStatus);
      if (status == AnimationStatus.completed) {
        then();
      }
    }

    animation.addStatusListener(handleStatus);
    return true;
  }
}

class GlassMorphButtonState extends State<GlassMorphButton>
    with _MorphOpener<GlassMorphButton> {
  bool _hidden = false;

  @override
  void _setHidden(bool hidden) => setState(() => _hidden = hidden);

  @override
  Widget _face() => widget.child;

  @override
  LiquidGlassStyle _styleOf(ColorScheme colorScheme) =>
      widget.styleOf(colorScheme);

  @override
  List<BoxShadow> _shadowsOf(ColorScheme colorScheme) => widget.shadows;

  @override
  Widget build(BuildContext context) {
    // Hidden, it takes no taps either: as its page returns, the route lets
    // taps through to the page below, which would open it again.
    return IgnorePointer(
      ignoring: _hidden,
      child: Opacity(
        opacity: _hidden ? 0 : 1,
        child: LiquidGlassButton(
          styleOf: widget.styleOf,
          shadows: widget.shadows,
          tooltip: widget.tooltip,
          onTap: () => widget.onTap(this),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A button on a pane of glass it shares, as one in a [GlassButtonGroup],
/// that opens a page out of itself as [GlassMorphButton] does: the page grows
/// out of where the button stands and returns into it as a drop of glass.
/// While the page is open the button's face stands hidden and the pane stays,
/// unless the button stands alone in its group, which is then the whole
/// button and hides as a [GlassMorphButton] does. [builder] builds the
/// button, which opens the page with [GlassMorphSourceState.toNamed]; it is
/// built in the morph too, under the button's themes but none of its other
/// ancestors, so it holds no [GlobalKey] and looks nothing up, as
/// `Scaffold.of`, as it builds. Off glass, [toNamed] is [Get.toNamed].
///
/// ```dart
/// GlassButtonGroup(
///   children: [
///     GlassMorphSource(
///       builder: (context, source) => IconButton(
///         tooltip: '搜索',
///         onPressed: () => source.toNamed('/settingsSearch'),
///         icon: const Icon(Icons.search),
///       ),
///     ),
///   ],
/// )
/// ```
class GlassMorphSource extends StatefulWidget {
  const GlassMorphSource({super.key, required this.builder});

  final Widget Function(BuildContext context, GlassMorphSourceState source)
  builder;

  @override
  State<GlassMorphSource> createState() => GlassMorphSourceState();
}

class GlassMorphSourceState extends State<GlassMorphSource>
    with _MorphOpener<GlassMorphSource> {
  bool _hidden = false;

  // Alone in its group, the button is the whole of it, pane and all.
  GlassButtonGroupState? get _whole {
    if (!mounted) {
      return null;
    }
    final group = GlassButtonGroup.maybeOf(context);
    return group != null && group.alone ? group : null;
  }

  bool get _glass =>
      GlassButtonGroup.maybeOf(context)?.glass ?? GlassSurfaces.installed;

  @override
  Future<T?>? toNamed<T>(
    String page, {
    Map<String, String>? parameters,
    dynamic arguments,
  }) {
    if (!_glass) {
      return Get.toNamed(page, parameters: parameters, arguments: arguments);
    }
    return super.toNamed(page, parameters: parameters, arguments: arguments);
  }

  @override
  RenderBox? get _box => _whole?.box ?? super._box;

  // The group hidden whole while this stood alone in it, which shows again
  // however it has changed meanwhile.
  GlassButtonGroupState? _hiddenGroup;

  @override
  void _setHidden(bool hidden) {
    if (hidden) {
      final group = _whole;
      group?.hidden = true;
      _hiddenGroup = group;
    } else {
      _hiddenGroup?.hidden = false;
      _hiddenGroup = null;
    }
    setState(() => _hidden = hidden);
  }

  @override
  void dispose() {
    // Gone before its page closed: the group shows again once the tree is
    // no longer coming down.
    if (_hiddenGroup case final group?) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => group.hidden = false,
      );
    }
    super.dispose();
  }

  @override
  Widget _face() =>
      Builder(builder: (context) => widget.builder(context, this));

  @override
  LiquidGlassStyle _styleOf(ColorScheme colorScheme) =>
      GlassButtonGroup.styleOf(colorScheme);

  // On a pane it shares, the glass it grows out of casts no shadow of its
  // own over the pane's.
  @override
  List<BoxShadow> _shadowsOf(ColorScheme colorScheme) =>
      _whole != null ? GlassButtonGroup.shadowsOf(colorScheme) : const [];

  @override
  Widget build(BuildContext context) {
    // Hidden, it takes no taps either, as a GlassMorphButton.
    return IgnorePointer(
      ignoring: _hidden,
      child: Opacity(
        opacity: _hidden ? 0 : 1,
        child: widget.builder(context, this),
      ),
    );
  }
}

/// What opens a page out of a button: the route it opened, which the button
/// stands hidden under from when the page first shows until it has closed,
/// and what the morph draws of the button.
mixin _MorphOpener<W extends StatefulWidget> on State<W> {
  TransitionRoute<dynamic>? _route;

  /// The button, whose rect the page grows from and returns into.
  RenderBox? get _box {
    if (!mounted) {
      return null;
    }
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  void _setHidden(bool hidden);

  /// The button's face, drawn in the glass as it leaves and as it returns.
  Widget _face();

  LiquidGlassStyle _styleOf(ColorScheme colorScheme);

  List<BoxShadow> _shadowsOf(ColorScheme colorScheme);

  /// Opens the page named [page] out of this button, as [Get.toNamed] does.
  /// With animations turned off, or no route by that name, it is
  /// [Get.toNamed].
  Future<T?>? toNamed<T>(
    String page, {
    Map<String, String>? parameters,
    dynamic arguments,
  }) {
    if (page == Get.currentRoute) {
      return null;
    }
    final navigator = Get.key.currentState;
    if (navigator == null ||
        _box == null ||
        MediaQuery.disableAnimationsOf(context)) {
      return Get.toNamed(page, parameters: parameters, arguments: arguments);
    }
    final name = parameters == null
        ? page
        : Uri(path: page, queryParameters: parameters).toString();
    // As Get.toNamed's pushNamed resolves it.
    final redirect = PageRedirect(
      settings: RouteSettings(name: name, arguments: arguments),
    );
    while (redirect.needRecheck()) {}
    final target = redirect.route;
    if (redirect.isUnknown || target == null) {
      return Get.toNamed(page, parameters: parameters, arguments: arguments);
    }
    // The page under it is the button's, if that is the top one and covers
    // the pages under it.
    final below = ModalRoute.of(context);
    final route = _GlassMorphRoute<T>(
      source: this,
      belowRoute: below != null && below.isCurrent && below.opaque
          ? below
          : null,
      page: target.page,
      parameter: target.parameters,
      settings: redirect.settings,
      binding: target.binding,
      bindings: target.bindings,
      middlewares: target.middlewares,
    );
    final opened = navigator.push(route);
    _route?.animation?.removeStatusListener(_handleRouteStatus);
    route.animation?.addStatusListener(_handleRouteStatus);
    route.completed.whenComplete(() => _shown(route));
    _route = route;
    // A route spends its first frame offstage, for heroes to measure, so
    // the button hides as the page first shows, a frame on.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route)) {
        _setHidden(true);
        route._coverBelowOnceDrawn();
      }
    });
    return opened;
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status.isDismissed) {
      _shown(_route);
    }
  }

  void _shown(TransitionRoute<dynamic>? route) {
    if (route == null || !identical(route, _route)) {
      return;
    }
    route.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    if (mounted) {
      _setHidden(false);
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    super.dispose();
  }
}

class _GlassMorphRoute<T> extends GetPageRoute<T> {
  _GlassMorphRoute({
    required this.source,
    this.belowRoute,
    super.settings,
    super.page,
    super.parameter,
    super.binding,
    super.bindings,
    super.middlewares,
  });

  final _MorphOpener<StatefulWidget> source;

  /// The route right under this one, the button's, when it covers the ones
  /// under it: only then does a picture of it stand in for all of them.
  final ModalRoute<dynamic>? belowRoute;

  // The page the button stands on, as it stood once the button hid, drawn
  // under the morph in its place: the navigator then leaves the page itself
  // unpainted, which would otherwise draw again every frame of the morph,
  // its own glass and all, there being no raster cache to keep it.
  _Below? _below;

  // The route's own animation. Its first frame, offstage for heroes to
  // measure, shows its pages a completed one in its place.
  Animation<double>? get _own => controller;

  @override
  void install() {
    super.install();
    // After TransitionRoute's own, which lets the page below show as the
    // route animates.
    animation!.addStatusListener(_keepBelowCovered);
  }

  @override
  void dispose() {
    _below?.image.dispose();
    _below = null;
    super.dispose();
  }

  // The navigator's size: the picture of the page below holds only while it
  // stays as it was taken, as a turned screen or a resized window lays the
  // page out anew.
  Size? get _screen => switch (navigator?.context.findRenderObject()) {
    final RenderBox box when box.hasSize => box.size,
    _ => null,
  };

  /// The picture of the page below, while it still fits the screen. Once it
  /// doesn't, it is let go a frame on, and the page itself shows again.
  _Below? get _fittingBelow {
    final below = _below;
    if (below == null || _screen == below.screen) {
      return below;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _dropBelow());
    return null;
  }

  void _dropBelow() {
    final below = _below;
    if (below == null) {
      return;
    }
    _below = null;
    below.image.dispose();
    if ((animation?.status.isAnimating ?? false) && overlayEntries.isNotEmpty) {
      overlayEntries.first.opaque = false;
    }
  }

  void _keepBelowCovered(AnimationStatus status) {
    if (_below == null || !status.isAnimating || overlayEntries.isEmpty) {
      return;
    }
    if (_screen != _below!.screen) {
      _dropBelow();
    } else {
      overlayEntries.first.opaque = true;
    }
  }

  // Once the page below has drawn without its button, a frame on, takes it,
  // if it is the page right under this one and covers the pages under it.
  void _coverBelowOnceDrawn() {
    final below = belowRoute;
    if (below == null) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final boundary = below.subtreeContext?.findRenderObject();
      if (_below != null ||
          !isCurrent ||
          !below.isActive ||
          !(animation?.status.isAnimating ?? false) ||
          boundary is! RenderRepaintBoundary ||
          !boundary.attached) {
        return;
      }
      // ignore: invalid_use_of_protected_member
      final layer = boundary.layer;
      if (layer is! OffsetLayer || !layer.supportsRasterization()) {
        return;
      }
      final screen = _screen;
      if (screen == null) {
        return;
      }
      _below = (
        // The page's own ratio, which the app's interface scale changes.
        image: boundary.toImageSync(
          pixelRatio:
              below.subtreeContext!
                  .getInheritedWidgetOfExactType<MediaQuery>()
                  ?.data
                  .devicePixelRatio ??
              1,
        ),
        rect: boundary.localToGlobal(Offset.zero) & boundary.size,
        screen: screen,
      );
      _keepBelowCovered(animation!.status);
    });
  }

  @override
  Duration get transitionDuration => _openDuration;

  @override
  Duration get reverseTransitionDuration => glassDropletReturn;

  // The page under it stays still as this one grows out of its button.
  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PageMorph(
      animation: animation,
      route: this,
      source: source,
      // A page opened over this one moves it as the app's transition does.
      child: super.buildTransitions(
        context,
        kAlwaysCompleteAnimation,
        secondaryAnimation,
        child,
      ),
    );
  }
}

class _PageMorph extends StatefulWidget {
  const _PageMorph({
    required this.animation,
    required this.route,
    required this.source,
    required this.child,
  });

  final Animation<double> animation;
  final _GlassMorphRoute<dynamic> route;
  final _MorphOpener<StatefulWidget> source;
  final Widget child;

  @override
  State<_PageMorph> createState() => _PageMorphState();
}

class _PageMorphState extends State<_PageMorph> {
  // Where the route stood when it began to close.
  double? _closedFrom;
  RenderBox? _sourceBox;

  // The keyboard's insets as the page began to morph, which it keeps until
  // it has: a keyboard rising or leaving with it would lay it out again
  // every frame.
  EdgeInsets? _insets;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(_PageMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.reverse:
        _closedFrom ??= _linear(widget.animation);
      case AnimationStatus.forward:
        _closedFrom = null;
      default:
    }
    if (mounted) {
      setState(() => _insets = null);
    }
  }

  static double _linear(Animation<double> animation) => switch (animation) {
    ProxyAnimation(:final parent?) => _linear(parent),
    CurvedAnimation(:final parent) => _linear(parent),
    _ => animation.value,
  };

  // Closing follows the route from its linear progress. A page closed before
  // it opened all the way plays the whole return in the time its route has
  // left.
  double? get _returnTime {
    final from = _closedFrom ?? 1;
    if (from <= 0) {
      return glassDropletReturnSeconds;
    }
    final left = _linear(widget.animation) / from;
    return (1 - left).clamp(0.0, 1.0) * glassDropletReturnSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final source = widget.source;
    final media = MediaQuery.of(context);
    if (widget.animation.status.isAnimating) {
      _insets ??= media.viewInsets;
    } else {
      _insets = null;
    }
    // The button's face, drawn in the glass as it leaves and as it returns:
    // a picture of it, out of reach of taps, the keyboard and screen readers,
    // or the page would hold a second, unseen button.
    final face = ExcludeSemantics(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            // Built again here, in the page's route: under the button's own
            // themes, so that it looks as the button does.
            child: source.mounted
                ? InheritedTheme.captureAll(source.context, source._face())
                : source._face(),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        if (source._box case final box?) {
          _sourceBox = box;
        }
        final status = widget.animation.status;
        return _Morph(
          openTime: status == AnimationStatus.forward
              ? _openPace.transform(_linear(widget.animation)) * _openSeconds
              : null,
          returnTime: status.isForwardOrCompleted ? null : _returnTime,
          source: _sourceBox,
          below: widget.route._fittingBelow,
          faceSize: _sourceBox?.size ?? Size.zero,
          buttonStyle: source._styleOf(colorScheme),
          pageStyle: LiquidGlassStyle.menu(colorScheme),
          buttonShadows: source._shadowsOf(colorScheme),
          colorScheme: colorScheme,
          devicePixelRatio: media.devicePixelRatio,
          children: [child!, face],
        );
      },
      child: MediaQuery(
        data: switch (_insets) {
          final insets? => media.copyWith(viewInsets: insets),
          null => media,
        },
        child: widget.child,
      ),
    );
  }
}

class _Morph extends MultiChildRenderObjectWidget {
  const _Morph({
    required this.openTime,
    required this.returnTime,
    required this.source,
    required this.below,
    required this.faceSize,
    required this.buttonStyle,
    required this.pageStyle,
    required this.buttonShadows,
    required this.colorScheme,
    required this.devicePixelRatio,
    required super.children,
  });

  /// Seconds into the page's opening, or its return, if under way.
  final double? openTime;
  final double? returnTime;

  /// The button, whose rect the page grows from and returns into.
  final RenderBox? source;

  /// The page under this one, drawn in its place while it morphs.
  final _Below? below;
  final Size faceSize;
  final LiquidGlassStyle buttonStyle;
  final LiquidGlassStyle pageStyle;
  final List<BoxShadow> buttonShadows;
  final ColorScheme colorScheme;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMorph()..update(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMorph).update(this);
  }
}

/// A picture of the page under a morphing one, and where it stands on screen.
/// [screen] is the navigator's size as it was taken.
typedef _Below = ({ui.Image image, Rect rect, Size screen});

class _MorphParentData extends ContainerBoxParentData<RenderBox> {}

/// The page, its first child, morphing out of and into its button, whose
/// face is its second.
class _RenderMorph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MorphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MorphParentData> {
  late final _pane = LiquidGlassPane(markNeedsPaint);
  final _clip = LayerHandle<ClipPathLayer>();
  final _transform = LayerHandle<TransformLayer>();
  final _filter = LayerHandle<ImageFilterLayer>();
  final _faceOpacity = LayerHandle<OpacityLayer>();
  final _faceTransform = LayerHandle<TransformLayer>();

  _Morph? _config;

  // How the page stands in its platter while it morphs, and where the face
  // stands; for hit tests and transforms as for paint.
  Matrix4? _pageTransform;

  // Whether the page is morphing, or opening, as last painted. While it
  // morphs it takes hits only where it is drawn, and while it opens it
  // takes the rest, so that a tap does not reach the hidden button.
  bool _morphing = false;
  bool _opening = false;
  Offset _faceOffset = Offset.zero;

  // How far the button is scaled on screen, as a header shrunk to fit
  // scales it: the face, laid out at the button's own size, is drawn so.
  double _faceScale = 1;

  // Where the button last was, and the page as it began to return.
  Rect? _lastAnchor;
  Rect? _lastPlatter;
  double _lastRadius = 0;
  double _lastContent = 1;
  double _lastFill = 1;
  Rect? _returnFrom;
  double _returnRadius = 0;
  double _returnContent = 1;
  double _returnFill = 1;

  // The page as an image, taken as it begins to open or to return, and
  // drawn through the morph as Flutter's own page transitions draw theirs,
  // rather than the page painted, faded and blurred offscreen each frame. A
  // page with a platform view in it can't be taken, and morphs as it is.
  ui.Image? _snapshot;
  bool _snapshotReturning = false;
  Size? _snapshotSize;
  bool _unsnappable = false;

  RenderBox get _page => firstChild!;
  RenderBox get _face => lastChild!;

  void update(_Morph config) {
    final old = _config;
    _config = config;
    if (old?.faceSize != config.faceSize) {
      markNeedsLayout();
    }
    markNeedsPaint();
    if (config.returnTime == null) {
      _returnFrom = null;
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MorphParentData) {
      child.parentData = _MorphParentData();
    }
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    _page.layout(BoxConstraints.tight(size));
    _face.layout(BoxConstraints.tight(_config!.faceSize));
  }

  @override
  void dispose() {
    _pane.dispose();
    _clear();
    _dropSnapshot();
    super.dispose();
  }

  void _dropSnapshot() {
    _snapshot?.dispose();
    _snapshot = null;
  }

  ui.Image? _pageImage() {
    if (_unsnappable) {
      return null;
    }
    final returning = _config!.returnTime != null;
    if (_snapshot case final snapshot?
        when _snapshotReturning == returning && _snapshotSize == size) {
      return snapshot;
    }
    _dropSnapshot();
    final layer = OffsetLayer();
    // As SnapshotWidget paints its child to take it.
    PaintingContext(layer, Offset.zero & size)
      ..paintChild(_page, Offset.zero)
      // ignore: invalid_use_of_protected_member
      ..stopRecordingIfNeeded();
    if (!layer.supportsRasterization()) {
      layer.dispose();
      _unsnappable = true;
      return null;
    }
    _snapshot = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _config!.devicePixelRatio,
    );
    layer.dispose();
    _snapshotReturning = returning;
    _snapshotSize = size;
    return _snapshot;
  }

  void _clear() {
    _pane.clear();
    _clip.layer = null;
    _transform.layer = null;
    _filter.layer = null;
    _faceOpacity.layer = null;
    _faceTransform.layer = null;
  }

  /// The button's rect in this box, or where it last was.
  Rect? _anchor() {
    if (_config?.source case final source? when source.attached) {
      final rect = MatrixUtils.transformRect(
        source.getTransformTo(this),
        Offset.zero & source.size,
      );
      if (rect.isFinite && !rect.isEmpty) {
        _lastAnchor = rect;
      }
    }
    return _lastAnchor;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _config!;
    final anchor = _anchor();
    _pageTransform = null;
    _morphing =
        anchor != null &&
        (config.openTime != null || config.returnTime != null);
    _opening = _morphing && config.returnTime == null;
    if (anchor == null || !_morphing) {
      _clear();
      _dropSnapshot();
      context.paintChild(_page, offset);
      return;
    }
    final faceWidth = _face.size.width;
    _faceScale = faceWidth > 0 ? anchor.width / faceWidth : 1;
    if (config.below case final below?) {
      final image = below.image;
      context.canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        below.rect.shift(globalToLocal(Offset.zero) + offset),
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    if (config.returnTime case final time?) {
      _paintReturn(context, offset, anchor, time);
    } else {
      _paintOpen(context, offset, anchor, config.openTime!);
    }
  }

  /// The opening [time] seconds on: the button's glass swells into the page,
  /// a platter growing out of it while the button's own drop sinks into it.
  void _paintOpen(
    PaintingContext context,
    Offset offset,
    Rect anchor,
    double time,
  ) {
    final config = _config!;
    final card = Offset.zero & size;
    final progress = _open.x(time);
    final settled = progress.clamp(0.0, 1.0);
    final scale = ui.lerpDouble(
      glassPlatterInControl * anchor.shortestSide / card.width,
      1,
      progress,
    )!;
    final height = ui.lerpDouble(card.width, card.height, progress)!;
    final toCard = card.center.dy - anchor.center.dy;
    final dip =
        toCard.sign *
        (math.min(1.0, toCard.abs() / 30) * 23 + 0.124 * toCard.abs()) *
        glassRiseAndFall(time, 0.098, 3.3);
    final platter = Rect.fromCenter(
      center:
          Offset.lerp(anchor.center, card.center, progress)! + Offset(0, dip),
      width: math.max(0.0, card.width * scale),
      height: math.max(0.0, height * scale),
    );
    final corners =
        card.width *
        _cornersReach *
        _corners.x(math.max(0.0, time - _cornersDelay));
    final radius = math.max(0.0, math.min(height / 2, corners) * scale);
    final extent = anchor.size * ui.lerpDouble(1, glassDropletShare, progress)!;
    final sunk = Offset.lerp(anchor.center, card.center, glassDropletShare)!;
    final droplet = Rect.fromCenter(
      center: Offset.lerp(
        anchor.center,
        _within(
          sunk,
          card.deflate(
            anchor.longestSide * glassDropletShare / 2 +
                glassDropletBlend +
                _rimDepth,
          ),
        ),
        progress,
      )!,
      width: extent.width,
      height: extent.height,
    );
    _lastPlatter = platter;
    _lastRadius = radius;
    // The glass swells first, and the page comes into it, quickly, as it
    // nears its size.
    _lastContent = Curves.easeOut.transform(_interval(0.6, 0.95, settled));
    _lastFill = Curves.easeIn.transform(_interval(0.55, 0.9, settled));
    _paintMorph(
      context,
      offset,
      anchor: anchor,
      platter: platter,
      radius: radius,
      droplet: droplet,
      blend: glassDropletBlend,
      style: LiquidGlassStyle.lerp(
        config.buttonStyle,
        config.pageStyle,
        settled,
      ),
      platterShadows: menuShadows(config.colorScheme, settled),
      dropletShadows: _scaled(config.buttonShadows, 1 - settled),
      fill: _lastFill,
      content: _lastContent,
      blur: math.sqrt(
        math.pow(7 * (1 - settled), 2) +
            math.pow(2.5 * glassRiseAndFall(time, 0.069, 2.1), 2),
      ),
      face: 1 - math.min(1.0, settled / 0.25),
      faceAt: anchor,
    );
  }

  /// The return into the button [time] seconds on, as a menu's: the platter
  /// dips away and shrinks toward the button, the page shrinking with it and
  /// frosting into its glass, while a droplet flows out of it and rises into
  /// the button, re-forming it.
  void _paintReturn(
    PaintingContext context,
    Offset offset,
    Rect anchor,
    double time,
  ) {
    final config = _config!;
    if (_returnFrom == null) {
      _returnFrom = _lastPlatter ?? Offset.zero & size;
      _returnRadius = _lastPlatter == null ? 0 : _lastRadius;
      _returnContent = _lastPlatter == null ? 1 : _lastContent;
      _returnFill = _lastPlatter == null ? 1 : _lastFill;
    }
    final (
      :platter,
      :radius,
      :droplet,
      :blend,
      :progress,
      :absorbed,
    ) = glassDropletReturnAt(
      from: _returnFrom!,
      fromRadius: _returnRadius,
      anchor: anchor,
      time: time,
    );
    final remaining = (1 - progress).clamp(0.0, 1.0);
    final shrunk = progress.clamp(0.0, 1.0);
    _paintMorph(
      context,
      offset,
      anchor: anchor,
      platter: platter,
      radius: radius,
      droplet: droplet,
      blend: blend,
      style: LiquidGlassStyle.lerp(
        config.buttonStyle,
        config.pageStyle,
        remaining,
      ),
      platterShadows: menuShadows(config.colorScheme, remaining),
      dropletShadows: _scaled(config.buttonShadows, shrunk),
      fill: _returnFill * (1 - _fillOut.transform(shrunk)),
      content: _returnContent * (1 - _contentOut.transform(shrunk)),
      blur: _returnFrost * shrunk,
      face: absorbed,
      faceAt: droplet,
    );
  }

  void _paintMorph(
    PaintingContext context,
    Offset offset, {
    required Rect anchor,
    required Rect platter,
    required double radius,
    required Rect droplet,
    required double blend,
    required LiquidGlassStyle style,
    required List<BoxShadow> platterShadows,
    required List<BoxShadow> dropletShadows,
    required double fill,
    required double content,
    required double blur,
    required double face,
    required Rect faceAt,
  }) {
    final config = _config!;
    final outline = gooPairOutline(platter, radius, droplet, blend);
    final shape = outline.getBounds();
    if (shape.isEmpty) {
      _clear();
      return;
    }
    final card = Offset.zero & size;
    // Under a full fill the glass would not show: most of the opening.
    if (fill < 1) {
      // The glass keeps the lighter glass's frost, the button's, all the
      // way: one capture held at it as it grows, and no frost past it. The
      // shader frosting the rest of the way to the page's ran every pixel
      // of a pane growing to the screen through a wide blur, 90 ms a frame
      // on a phone; the page's fill covers the glass as it nears its size,
      // so the frost it would have reached hardly shows.
      final frost = math.min(config.buttonStyle.blur, config.pageStyle.blur);
      _pane.paint(
        context,
        shape.shift(offset),
        shape: LiquidGlassGoo(
          outline.shift(-shape.topLeft),
          [platter.shift(-shape.topLeft), droplet.shift(-shape.topLeft)],
          [blend],
          firstRadius: math.max(radius, 1e-3),
        ),
        style: style.copyWith(blur: math.min(style.blur, frost)),
        // A capture taken at each frame would redraw what lies behind, the
        // whole screen, frame after frame.
        hold: card
            .expandToInclude(anchor.inflate(anchor.longestSide))
            .inflate(size.longestSide * 0.1)
            .shift(offset),
        holdFrost: frost,
      );
    } else {
      _pane.clear();
    }
    final canvas = context.canvas;
    final path = outline.shift(offset);
    paintGlassShadowsOutside(
      canvas,
      path,
      platter.shift(offset),
      radius,
      platterShadows,
    );
    paintGlassShadowsOutside(
      canvas,
      path,
      droplet.shift(offset),
      droplet.shortestSide / 2,
      dropletShadows,
    );
    if (fill > 0) {
      canvas.drawPath(
        path,
        Paint()..color = config.colorScheme.surface.withValues(alpha: fill),
      );
    }
    _paintFace(context, offset, faceAt, face);
    _paintPage(context, offset, platter, radius, content, blur);
  }

  // The button's face, centred where the button stands or its droplet is.
  void _paintFace(
    PaintingContext context,
    Offset offset,
    Rect at,
    double opacity,
  ) {
    final scale = _faceScale;
    final size = _face.size * scale;
    _faceOffset = at.center - Offset(size.width / 2, size.height / 2);
    if (opacity <= 0) {
      _faceOpacity.layer = null;
      _faceTransform.layer = null;
      return;
    }
    _faceOpacity.layer = context.pushOpacity(
      offset + _faceOffset,
      (opacity * 255).round(),
      (context, offset) {
        if (scale == 1) {
          _faceTransform.layer = null;
          context.paintChild(_face, offset);
          return;
        }
        _faceTransform.layer = context.pushTransform(
          needsCompositing,
          offset,
          Matrix4.diagonal3Values(scale, scale, 1),
          (context, offset) => context.paintChild(_face, offset),
          oldLayer: _faceTransform.layer,
        );
      },
      oldLayer: _faceOpacity.layer,
    );
  }

  // The page, shrunk into its platter and clipped to it, blurred by [blur]
  // as it shows on screen: a blur shrinks with what it blurs, and the page
  // shrunk to a third would otherwise show a third of it.
  void _paintPage(
    PaintingContext context,
    Offset offset,
    Rect platter,
    double radius,
    double opacity,
    double blur,
  ) {
    if (opacity <= 0 || platter.isEmpty) {
      _clip.layer = null;
      _transform.layer = null;
      _filter.layer = null;
      return;
    }
    final scale = platter.width / size.width;
    final sigma = blur > _blurUnseen ? math.min(blur / scale, _blurMost) : 0.0;
    final transform = Matrix4.identity()
      ..translateByDouble(platter.left, platter.top, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _pageTransform = transform;
    if (_pageImage() case final image?) {
      _clip.layer = null;
      _transform.layer = null;
      _filter.layer = null;
      final paint = Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, opacity);
      if (sigma > 0) {
        paint.imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        );
      }
      context.canvas
        ..save()
        ..clipRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            platter.shift(offset),
            Radius.circular(radius),
          ),
        )
        ..translate(offset.dx + platter.left, offset.dy + platter.top)
        ..scale(scale)
        ..drawImageRect(
          image,
          Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
          Offset.zero & size,
          paint,
        )
        ..restore();
      return;
    }
    // The fade and the blur in one pass offscreen, the page's size, and none
    // once a blur would no longer show.
    ui.ImageFilter? filter;
    if (sigma > 0) {
      filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    }
    if (opacity < 1) {
      final fade = ColorFilter.matrix([
        ...[1, 0, 0, 0, 0],
        ...[0, 1, 0, 0, 0],
        ...[0, 0, 1, 0, 0],
        ...[0, 0, 0, opacity, 0],
      ]);
      filter = filter == null
          ? fade
          : ui.ImageFilter.compose(outer: fade, inner: filter);
    }
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      platter,
      Path()..addRSuperellipse(
        RSuperellipse.fromRectAndRadius(platter, Radius.circular(radius)),
      ),
      (context, offset) {
        _transform.layer = context.pushTransform(
          needsCompositing,
          offset,
          transform,
          (context, offset) {
            if (filter == null) {
              _filter.layer = null;
              context.paintChild(_page, offset);
            } else {
              context.pushLayer(
                (_filter.layer ??= ImageFilterLayer())..imageFilter = filter,
                (context, offset) => context.paintChild(_page, offset),
                offset,
              );
            }
          },
          oldLayer: _transform.layer,
        );
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (identical(child, _face)) {
      transform
        ..translateByDouble(_faceOffset.dx, _faceOffset.dy, 0, 1)
        ..scaleByDouble(_faceScale, _faceScale, 1, 1);
    } else if (_pageTransform case final page?) {
      transform.multiply(page);
    }
  }

  @override
  bool hitTestSelf(Offset position) => _opening;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final transform = _pageTransform;
    if (transform == null) {
      return !_morphing && _page.hitTest(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (result, position) => _page.hitTest(result, position: position),
    );
  }

  static double _interval(double begin, double end, double t) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  static Offset _within(Offset point, Rect rect) => Offset(
    rect.width >= 0 ? point.dx.clamp(rect.left, rect.right) : rect.center.dx,
    rect.height >= 0 ? point.dy.clamp(rect.top, rect.bottom) : rect.center.dy,
  );

  static List<BoxShadow> _scaled(List<BoxShadow> shadows, double amount) => [
    for (final shadow in shadows)
      shadow.copyWith(
        color: shadow.color.withValues(alpha: shadow.color.a * amount),
      ),
  ];
}
