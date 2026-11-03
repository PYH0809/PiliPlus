// After Flutter's container transform, OpenContainer
// (https://github.com/flutter/packages, animations/lib/src/open_container.dart,
// BSD-3-Clause), on GetX's routes: a video card grows into the video page,
// its cover into the player, and the page shrinks back into the card as it
// closes, as YouTube's do.

import 'dart:async';
import 'dart:ui' as ui show Image, lerpDouble;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// As long as OpenContainer's, both ways.
const videoExpandDuration = Duration(milliseconds: 300);

// The fade through from the card to the page, on the route's linear time:
// the card fades out over its first fifth, the page in over the rest. On
// the return OpenContainer flips the weights, so that the same plays
// backwards in time: the page fades out over the first fifth of the
// return, and the card in over the rest.
const _fadeShare = 0.2;

// The scrim OpenContainer lays over the page below, at most.
const _scrimColor = Colors.black54;

// The cover held over the player until the video's first frame shows fades
// out over this, and at most this long after the page has opened.
const _coverFade = Duration(milliseconds: 200);
const _coverHoldAtMost = Duration(seconds: 4);

/// Where the card, the page and the cover stand [t] into the route's
/// animation, its linear value, as OpenContainer lays its container out.
@immutable
class VideoExpandFrame {
  const VideoExpandFrame({
    required this.progress,
    required this.rect,
    required this.radius,
    required this.cardOpacity,
    required this.pageOpacity,
    required this.scrim,
    required this.cover,
    required this.coverOpacity,
  });

  /// The frame [t] into the opening, or into the return when [returning].
  /// The rect and its corners run on [Curves.fastOutSlowIn], and on its
  /// flip on the return, or linearly when the return [interrupted] the
  /// opening; a return that interrupted the opening also keeps the opening's
  /// fades, run backwards, so nothing jumps. [card] is the card's rect,
  /// [screen] the page's, [coverFrom] the card's cover and [coverTo] the
  /// player; [videoShown] says the video has shown over the cover, which
  /// fades back in over it as the page fades out.
  factory VideoExpandFrame.at(
    double t, {
    required bool returning,
    bool interrupted = false,
    required Rect card,
    required Rect screen,
    double radius = 12,
    Rect? coverFrom,
    Rect? coverTo,
    bool videoShown = false,
  }) {
    final shape = !returning
        ? Curves.fastOutSlowIn.transform(t)
        : interrupted
        ? t
        : Curves.fastOutSlowIn.flipped.transform(t);
    final double cardOpacity;
    final double pageOpacity;
    final double scrim;
    if (!returning || interrupted) {
      cardOpacity = 1 - _within(t, 0, _fadeShare);
      pageOpacity = _within(t, _fadeShare, 1);
      scrim = _within(t, 0, _fadeShare);
    } else {
      cardOpacity = 1 - _within(t, 0, 1 - _fadeShare);
      pageOpacity = _within(t, 1 - _fadeShare, 1);
      scrim = shape;
    }
    return VideoExpandFrame(
      progress: shape,
      rect: Rect.lerp(card, screen, shape)!,
      radius: ui.lerpDouble(radius, 0, shape)!,
      cardOpacity: cardOpacity,
      pageOpacity: pageOpacity,
      scrim: scrim,
      cover: coverFrom == null || coverTo == null
          ? null
          : Rect.lerp(coverFrom, coverTo, shape),
      coverOpacity: returning && !interrupted && videoShown
          ? 1 - pageOpacity
          : 1,
    );
  }

  /// How far the rect has grown from the card to the screen.
  final double progress;

  /// The page's rect, clipped to it with corners of [radius].
  final Rect rect;
  final double radius;

  /// How far the picture of the card, fading out, and the page, fading in,
  /// show.
  final double cardOpacity;
  final double pageOpacity;

  /// How far the scrim over the page below has darkened, of [_scrimColor].
  final double scrim;

  /// The cover's rect, on its way from the card to the player, if both are
  /// known, and how far it shows.
  final Rect? cover;
  final double coverOpacity;

  static double _within(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}

/// Whether a video opens out of its card.
abstract final class VideoExpand {
  /// Whether a card opens its video by growing into it: only on phones and
  /// tablets, with the 视频展开动画 switch on and animations not turned off.
  static bool enabled(BuildContext context) => allows(
    setting: Pref.videoExpand,
    disableAnimations: MediaQuery.disableAnimationsOf(context),
    mobile: debugMobile ?? PlatformUtils.isMobile,
  );

  @visibleForTesting
  static bool allows({
    required bool setting,
    required bool disableAnimations,
    required bool mobile,
  }) => setting && !disableAnimations && mobile;

  /// Stands in for the platform in tests, which run on a desktop.
  @visibleForTesting
  static bool? debugMobile;
}

/// A video card that opens its video by growing into the page, its cover
/// into the player, as YouTube's do. [builder] builds the card, wrapping its
/// cover, without its badges, in [VideoExpandSourceState.cover], and hands
/// the source to `PageUtils.toVideoPage`. While the page is open the card
/// stands hidden under it.
class VideoExpandSource extends StatefulWidget {
  const VideoExpandSource({
    super.key,
    required this.color,
    required this.builder,
    this.radius = 12,
    this.coverRadius = BorderRadius.zero,
  });

  /// The card's own fill, which the page's fades in over.
  final Color color;

  /// The card's corners, which straighten as it grows, and the cover's.
  final double radius;
  final BorderRadius coverRadius;

  final Widget Function(BuildContext context, VideoExpandSourceState source)
  builder;

  @override
  State<VideoExpandSource> createState() => VideoExpandSourceState();
}

class VideoExpandSourceState extends State<VideoExpandSource> {
  final _cardKey = GlobalKey();
  final _coverKey = GlobalKey();
  bool _hidden = false;
  VideoExpandRoute<dynamic>? _route;

  /// Wraps the card's cover, which grows into the player.
  Widget cover(Widget child) => KeyedSubtree(key: _coverKey, child: child);

  /// [box]'s rect on screen, if it is laid out there.
  static Rect? _rectOf(RenderObject? box) {
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return rect.isFinite && !rect.isEmpty ? rect : null;
  }

  Rect? get _cardRect =>
      mounted ? _rectOf(_cardKey.currentContext?.findRenderObject()) : null;

  Rect? get _coverRect =>
      mounted ? _rectOf(_coverKey.currentContext?.findRenderObject()) : null;

  // The cover's picture as the card shows it, decoded already: a handle of
  // its own on the image of the first RenderImage under the cover.
  ui.Image? _coverImage() {
    ui.Image? image;
    void visit(RenderObject object) {
      if (image != null) {
        return;
      }
      if (object is RenderImage && object.image != null) {
        image = object.image!.clone();
        return;
      }
      object.visitChildren(visit);
    }

    if (_coverKey.currentContext?.findRenderObject() case final box?) {
      visit(box);
    }
    return image;
  }

  // The card as it was last painted, which fades out as the page grows.
  ui.Image? _cardImage(double pixelRatio) {
    final boundary = _cardKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer || !layer.supportsRasterization()) {
      return null;
    }
    return boundary.toImageSync(pixelRatio: pixelRatio);
  }

  /// Opens the page named [page] out of this card, as [Get.toNamed] does,
  /// and returns what it pops with. Null when it can't: animations are off,
  /// the card is off screen, or no route goes by that name; the caller then
  /// opens the page as it would have. Tapped again while its page opens, it
  /// opens nothing more.
  Future<T?>? expand<T>(String page, {dynamic arguments}) {
    if (_route case final route?) {
      return route.popped.then((value) => value as T?);
    }
    final navigator = Get.key.currentState;
    final screen = _rectOf(navigator?.context.findRenderObject());
    final card = _cardRect;
    if (navigator == null ||
        !mounted ||
        !VideoExpand.enabled(context) ||
        screen == null ||
        card == null ||
        !screen.overlaps(card)) {
      return null;
    }
    // As Get.toNamed's pushNamed resolves it.
    final redirect = PageRedirect(
      settings: RouteSettings(name: page, arguments: arguments),
    );
    while (redirect.needRecheck()) {}
    final target = redirect.route;
    if (redirect.isUnknown || target == null) {
      return null;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final route = VideoExpandRoute<T>(
      source: this,
      cardImage: _cardImage(pixelRatio),
      cover: _coverImage(),
      page: target.page,
      parameter: target.parameters,
      settings: redirect.settings,
      binding: target.binding,
      bindings: target.bindings,
      middlewares: target.middlewares,
    );
    final opened = navigator.push(route);
    _route = route;
    route.animation!.addStatusListener(_handleRouteStatus);
    route.completed.whenComplete(() => _shown(route));
    // A route spends its first frame offstage, so the card hides as the page
    // first shows, a frame on.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route)) {
        setState(() => _hidden = true);
      }
    });
    return opened;
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status.isDismissed) {
      _shown(_route);
    }
  }

  void _shown(VideoExpandRoute<dynamic>? route) {
    if (route == null || !identical(route, _route)) {
      return;
    }
    route.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    if (mounted) {
      setState(() => _hidden = false);
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hidden, it takes no taps either: as its page returns, the route lets
    // taps through to the page below, which would open it again.
    return IgnorePointer(
      ignoring: _hidden,
      child: Opacity(
        opacity: _hidden ? 0 : 1,
        child: RepaintBoundary(
          key: _cardKey,
          child: widget.builder(context, this),
        ),
      ),
    );
  }
}

/// The video page's route, opened out of a [VideoExpandSource]: the page
/// grows out of the card, the cover into the player, which the page marks
/// with a [VideoExpandTarget].
class VideoExpandRoute<T> extends GetPageRoute<T> {
  VideoExpandRoute({
    required this.source,
    required this.cardImage,
    required this.cover,
    super.settings,
    super.page,
    super.parameter,
    super.binding,
    super.bindings,
    super.middlewares,
  });

  final VideoExpandSourceState source;

  /// A picture of the card and its cover, taken as it opened. The route
  /// owns them.
  final ui.Image? cardImage;
  final ui.Image? cover;

  /// The page's player, where the cover grows into.
  VideoExpandTargetState? _target;

  /// Whether the video has shown over the cover.
  bool _videoShown = false;

  /// The route [context] is in, if a card opened it.
  static VideoExpandRoute<dynamic>? of(BuildContext context) =>
      switch (ModalRoute.of(context)) {
        final VideoExpandRoute<dynamic> route => route,
        _ => null,
      };

  @override
  void dispose() {
    cardImage?.dispose();
    cover?.dispose();
    super.dispose();
  }

  @override
  Duration get transitionDuration => videoExpandDuration;

  @override
  Duration get reverseTransitionDuration => videoExpandDuration;

  // The page under it stays still under the scrim, as OpenContainer's.
  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _ExpandTransition(
      animation: animation,
      route: this,
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

class _ExpandTransition extends StatefulWidget {
  const _ExpandTransition({
    required this.animation,
    required this.route,
    required this.child,
  });

  final Animation<double> animation;
  final VideoExpandRoute<dynamic> route;
  final Widget child;

  @override
  State<_ExpandTransition> createState() => _ExpandTransitionState();
}

class _ExpandTransitionState extends State<_ExpandTransition> {
  // Whether the page has opened all the way since it last set off, and
  // whether the return it is on interrupted its opening.
  bool _opened = false;
  bool _interrupted = false;

  // How the page returns when its card is gone or off screen: a plain fade.
  bool _returnsPlain = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(_ExpandTransition oldWidget) {
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
      case AnimationStatus.completed:
        _opened = true;
      case AnimationStatus.forward:
        _opened = false;
        _interrupted = false;
        _returnsPlain = false;
      case AnimationStatus.reverse:
        _interrupted = !_opened;
        // As OpenContainer measures the card again as it returns: if it has
        // gone, or scrolled off, there is nothing to return into.
        final card = widget.route.source._cardRect;
        final screen = VideoExpandSourceState._rectOf(
          context.findRenderObject(),
        );
        _returnsPlain =
            card == null || screen == null || !screen.overlaps(card);
      case AnimationStatus.dismissed:
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final source = route.source;
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        final status = widget.animation.status;
        return _Expand(
          t: widget.animation.value,
          animating: status.isAnimating,
          returning: status == AnimationStatus.reverse,
          interrupted: _interrupted,
          returnsPlain: _returnsPlain,
          card: source._cardRect,
          coverFrom: source._coverRect,
          player: route._target?._box,
          videoShown: route._videoShown,
          radius: source.widget.radius,
          coverRadius: source.widget.coverRadius,
          cardColor: source.widget.color,
          pageColor: Theme.of(context).scaffoldBackgroundColor,
          topPadding: MediaQuery.paddingOf(context).top,
          cardImage: route.cardImage,
          cover: route.cover,
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}

class _Expand extends SingleChildRenderObjectWidget {
  const _Expand({
    required this.t,
    required this.animating,
    required this.returning,
    required this.interrupted,
    required this.returnsPlain,
    required this.card,
    required this.coverFrom,
    required this.player,
    required this.videoShown,
    required this.radius,
    required this.coverRadius,
    required this.cardColor,
    required this.pageColor,
    required this.topPadding,
    required this.cardImage,
    required this.cover,
    required super.child,
  });

  final double t;
  final bool animating;
  final bool returning;
  final bool interrupted;
  final bool returnsPlain;
  final Rect? card;
  final Rect? coverFrom;
  final RenderBox? player;
  final bool videoShown;
  final double radius;
  final BorderRadius coverRadius;
  final Color cardColor;
  final Color pageColor;
  final double topPadding;
  final ui.Image? cardImage;
  final ui.Image? cover;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExpand()..config = this;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderExpand).config = this;
  }
}

/// The page, its child, growing out of the card and shrinking back into it,
/// with the scrim under it and the cover over it.
class _RenderExpand extends RenderProxyBox {
  final _clip = LayerHandle<ClipRRectLayer>();
  final _opacity = LayerHandle<OpacityLayer>();
  final _transform = LayerHandle<TransformLayer>();

  // Where the card last was, should it leave the screen as the page opens.
  Rect? _lastCard;
  Rect? _lastCover;

  _Expand? _config;
  set config(_Expand value) {
    _config = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    _clip.layer = null;
    _opacity.layer = null;
    _transform.layer = null;
  }

  // [rect], on screen, in this box.
  Rect _local(Rect rect) => rect.shift(globalToLocal(Offset.zero));

  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _config!;
    final page = child!;
    if (!config.animating) {
      _clear();
      context.paintChild(page, offset);
      return;
    }
    final screen = Offset.zero & size;
    final canvas = context.canvas;
    if (config.returnsPlain) {
      _paintPlain(context, offset, page);
      return;
    }
    if (config.card case final card?) {
      _lastCard = _local(card);
    }
    if (config.coverFrom case final cover?) {
      _lastCover = _local(cover);
    }
    final card = _lastCard;
    if (card == null) {
      _paintPlain(context, offset, page);
      return;
    }
    Rect? player;
    if (config.player case final box? when box.attached && box.hasSize) {
      player = MatrixUtils.transformRect(
        box.getTransformTo(this),
        Offset.zero & box.size,
      );
    }
    final frame = VideoExpandFrame.at(
      config.t,
      returning: config.returning,
      interrupted: config.interrupted,
      card: card,
      screen: screen,
      radius: config.radius,
      coverFrom: _lastCover,
      // Until the page has laid its player out, where it most often is.
      coverTo:
          player ??
          Rect.fromLTWH(0, config.topPadding, size.width, size.width * 9 / 16),
      videoShown: config.videoShown,
    );
    if (frame.scrim > 0) {
      canvas.drawRect(
        screen.shift(offset),
        Paint()
          ..color = _scrimColor.withValues(
            alpha: _scrimColor.a * frame.scrim,
          ),
      );
    }
    final rrect = RRect.fromRectAndRadius(
      frame.rect,
      Radius.circular(frame.radius),
    );
    canvas.drawRRect(
      rrect.shift(offset),
      Paint()
        ..color = Color.lerp(
          config.cardColor,
          config.pageColor,
          1 - frame.cardOpacity,
        )!,
    );
    if (config.cardImage case final image? when frame.cardOpacity > 0) {
      // Scaled to the container's width from its top, as OpenContainer fits
      // the card it fades out.
      final rect = frame.rect.shift(offset);
      canvas
        ..save()
        ..clipRRect(rrect.shift(offset))
        ..drawImageRect(
          image,
          Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(
            rect.left,
            rect.top,
            rect.width,
            rect.width * card.height / card.width,
          ),
          Paint()
            ..filterQuality = FilterQuality.low
            ..color = Color.fromRGBO(0, 0, 0, frame.cardOpacity),
        )
        ..restore();
    }
    if (frame.pageOpacity > 0) {
      _clip.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        frame.rect,
        rrect,
        (context, offset) {
          if (frame.pageOpacity >= 1) {
            _opacity.layer = null;
            context.paintChild(page, offset);
            return;
          }
          _opacity.layer = context.pushOpacity(
            offset,
            (frame.pageOpacity * 255).round(),
            (context, offset) => context.paintChild(page, offset),
            oldLayer: _opacity.layer,
          );
        },
        oldLayer: _clip.layer,
      );
    } else {
      _clip.layer = null;
      _opacity.layer = null;
    }
    _transform.layer = null;
    if ((config.cover, frame.cover) case (final image?, final at?)
        when frame.coverOpacity > 0) {
      _paintCover(
        context.canvas,
        image,
        at.shift(offset),
        BorderRadius.lerp(
          config.coverRadius,
          BorderRadius.zero,
          frame.progress,
        )!,
        frame.coverOpacity,
      );
    }
  }

  // The page fading in or out over the screen, a little shrunk, when there
  // is no card to grow out of or return into.
  void _paintPlain(PaintingContext context, Offset offset, RenderBox page) {
    final config = _config!;
    final t = config.t;
    final shape = Curves.fastOutSlowIn.transform(t);
    final screen = Offset.zero & size;
    context.canvas.drawRect(
      screen.shift(offset),
      Paint()..color = _scrimColor.withValues(alpha: _scrimColor.a * t),
    );
    _clip.layer = null;
    final scale = ui.lerpDouble(0.9, 1, shape)!;
    final center = screen.center;
    _transform.layer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.identity()
        ..translateByDouble(center.dx, center.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-center.dx, -center.dy, 0, 1),
      (context, offset) {
        _opacity.layer = context.pushOpacity(
          offset,
          (t * 255).round(),
          (context, offset) => context.paintChild(page, offset),
          oldLayer: _opacity.layer,
        );
      },
      oldLayer: _transform.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_transform.layer?.transform case final matrix?) {
      transform.multiply(matrix);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_transform.layer?.transform case final matrix?) {
      return result.addWithPaintTransform(
        transform: matrix,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );
    }
    return super.hitTestChildren(result, position: position);
  }
}

/// The cover [image] fitted to cover [rect], cropped to it with [radius].
void _paintCover(
  Canvas canvas,
  ui.Image image,
  Rect rect,
  BorderRadius radius,
  double opacity,
) {
  final imageSize = Size(image.width.toDouble(), image.height.toDouble());
  final fitted = applyBoxFit(BoxFit.cover, imageSize, rect.size);
  final source = Alignment.center.inscribe(
    fitted.source,
    Offset.zero & imageSize,
  );
  canvas
    ..save()
    ..clipRRect(radius.toRRect(rect))
    ..drawImageRect(
      image,
      source,
      rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    )
    ..restore();
}

/// Marks the video page's player, which the cover of the card it opened
/// from grows into, and holds the cover there until the video's first frame
/// shows: [watchVideo] calls back once it has, and returns what stops it
/// watching. On a page no card opened it is an empty box.
class VideoExpandTarget extends StatefulWidget {
  const VideoExpandTarget({super.key, required this.watchVideo});

  final VoidCallback Function(VoidCallback shown) watchVideo;

  @override
  State<VideoExpandTarget> createState() => VideoExpandTargetState();
}

class VideoExpandTargetState extends State<VideoExpandTarget>
    with SingleTickerProviderStateMixin {
  VideoExpandRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  late final _fade = AnimationController(
    vsync: this,
    duration: _coverFade,
    value: 1,
  );
  VoidCallback? _stopWatching;
  Timer? _holdTimer;
  bool _videoShown = false;
  bool _opened = false;
  bool _gone = false;

  RenderBox? get _box => switch (context.findRenderObject()) {
    final RenderBox box when box.attached && box.hasSize => box,
    _ => null,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = VideoExpandRoute.of(context);
    if (identical(route, _route)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    if (identical(_route?._target, this)) {
      _route!._target = null;
    }
    _route = route;
    _routeAnimation = route?.animation;
    if (route == null || route.cover == null) {
      return;
    }
    route._target = this;
    _routeAnimation!.addStatusListener(_handleRouteStatus);
    _opened = _routeAnimation!.isCompleted;
    _stopWatching ??= widget.watchVideo(_handleVideoShown);
  }

  void _handleRouteStatus(AnimationStatus status) {
    final opened = status.isCompleted;
    if (opened != _opened && mounted) {
      setState(() => _opened = opened);
      if (opened) {
        _fadeOnceShown();
      }
    }
  }

  void _handleVideoShown() {
    _stopWatching?.call();
    _stopWatching = () {};
    if (mounted) {
      _videoShown = true;
      _fadeOnceShown();
    }
  }

  void _fadeOnceShown() {
    if (!_opened || _gone) {
      return;
    }
    if (_videoShown) {
      _fadeOut();
    } else {
      // Not past this, should the video never say it has shown.
      _holdTimer ??= Timer(_coverHoldAtMost, _fadeOut);
    }
  }

  void _fadeOut() {
    _holdTimer?.cancel();
    if (!mounted || _gone || !_fade.isCompleted) {
      return;
    }
    _fade.reverse().whenComplete(() {
      if (mounted) {
        _route?._videoShown = true;
        setState(() => _gone = true);
      }
    });
  }

  @override
  void dispose() {
    _stopWatching?.call();
    _holdTimer?.cancel();
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    if (identical(_route?._target, this)) {
      _route!._target = null;
    }
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cover = _route?.cover;
    if (cover == null || !_opened || _gone) {
      return const SizedBox.expand();
    }
    // Over the player, out of reach of taps, until the video shows.
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: _CoverPainter(cover, _fade)),
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.image, this.opacity) : super(repaint: opacity);

  final ui.Image image;
  final Animation<double> opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity.value > 0) {
      _paintCover(
        canvas,
        image,
        Offset.zero & size,
        BorderRadius.zero,
        opacity.value,
      );
    }
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) =>
      !identical(oldDelegate.image, image);
}
