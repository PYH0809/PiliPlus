// After Flutter's container transform, OpenContainer
// (https://github.com/flutter/packages, animations/lib/src/open_container.dart,
// BSD-3-Clause), on GetX's routes: a video card grows into the video page,
// its cover into the player, and the page shrinks back into the card as it
// closes, as YouTube's do.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Image, lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart'
    show touchSlopH;
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/gestures.dart' show kTouchSlop;
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

// A card whose content moves into its page, as a dynamic into its detail:
// the page fades in over the last of the route's linear time, and the
// content, drawn from the card, fades out over the last quarter, so the two
// cross as the content lands; the same, backwards, as it returns.
const _contentPageFrom = 0.7;
const _contentFadeFrom = 0.75;

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
    this.content,
    this.contentOpacity = 0,
  });

  /// The frame [t] into the opening, or into the return when [returning].
  /// The rect and its corners run on [Curves.fastOutSlowIn], and on its
  /// flip on the return; a return that [interrupted] the opening runs it
  /// backwards, its curve and fades and all, so nothing jumps, as
  /// OpenContainer's CurvedAnimation does with no reverse curve. [card] is the card's rect,
  /// [screen] the page's, [coverFrom] the card's cover and [coverTo] the
  /// player; [videoShown] says the video has shown over the cover, which
  /// fades back in over it as the page fades out. With [contentTo], where
  /// the page lays the card's content out, the card's picture moves there
  /// instead of fading out, its top left corner onto that one's at its own
  /// size, shrunk only to fit, as the content may run longer on the page.
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
    Rect? contentTo,
  }) {
    final shape = returning && !interrupted
        ? Curves.fastOutSlowIn.flipped.transform(t)
        : Curves.fastOutSlowIn.transform(t);
    if (contentTo != null) {
      // At its own size, so its text stands as large as the page's, but no
      // wider than the page lays it out.
      final scale = math.min(1.0, contentTo.width / card.width);
      final landed = Rect.fromLTWH(
        contentTo.left,
        contentTo.top,
        card.width * scale,
        card.height * scale,
      );
      return VideoExpandFrame(
        progress: shape,
        rect: Rect.lerp(card, screen, shape)!,
        radius: ui.lerpDouble(radius, 0, shape)!,
        cardOpacity: 0,
        pageOpacity: _within(t, _contentPageFrom, 1),
        scrim: !returning || interrupted ? _within(t, 0, _fadeShare) : shape,
        cover: null,
        coverOpacity: 0,
        content: Rect.lerp(card, landed, shape),
        contentOpacity: 1 - _within(t, _contentFadeFrom, 1),
      );
    }
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

  /// The card's picture, moving onto the content the page lays out, and how
  /// far it shows.
  final Rect? content;
  final double contentOpacity;

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
    this.takesPressShot = true,
  });

  /// Whether a press on the cover takes the page below before the tap, as
  /// the opening's first frame would: false while a tap does not open the
  /// page, as in multi-select. A card whose tap opens something else only
  /// now and then, as an audio or a bangumi entry, can leave it on: the
  /// picture is drawn while the finger holds still and the screen with it,
  /// one for the whole app, let go within half a second.
  final bool takesPressShot;

  /// The card's own fill, which the page's fades in over.
  final Color color;

  /// The card's corners, which straighten as it grows, and the cover's.
  final double radius;
  final BorderRadius coverRadius;

  final Widget Function(BuildContext context, VideoExpandSourceState source)
  builder;

  /// The source the card around [context] opens from, for the parts of a
  /// card built apart from its [builder], such as a dynamic's video.
  static VideoExpandSourceState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<VideoExpandSourceState>();

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
  // its own on the image of the first RenderImage under the cover, and the
  // color it blends in, as the tint NetworkImgLayer gives covers in the dark.
  // Not a placeholder's, from the app's assets, shown until the cover loads.
  (ui.Image, ColorFilter?)? _coverImage() {
    RenderImage? found;
    void visit(Element element, bool placeholder) {
      if (found != null) {
        return;
      }
      if (element.widget case Image(:final image)) {
        placeholder = _isAsset(image);
      }
      if (!placeholder && element is RenderObjectElement) {
        if (element.renderObject case final RenderImage image
            when image.image != null) {
          found = image;
          return;
        }
      }
      element.visitChildren((child) => visit(child, placeholder));
    }

    if (_coverKey.currentContext case final Element element) {
      visit(element, false);
    }
    final image = found;
    if (image == null) {
      return null;
    }
    return (
      image.image!.clone(),
      switch (image.color) {
        final color? => ColorFilter.mode(
          color,
          image.colorBlendMode ?? BlendMode.srcIn,
        ),
        null => null,
      },
    );
  }

  static bool _isAsset(ImageProvider<Object> provider) => switch (provider) {
    AssetBundleImageProvider() => true,
    ResizeImage(:final imageProvider) => _isAsset(imageProvider),
    _ => false,
  };

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
    // As last composited: a tap's ink may have marked it to paint again.
    return layer.toImageSync(
      Offset.zero & boundary.size,
      pixelRatio: pixelRatio,
    );
  }

  /// Opens the page named [page] out of this card, as [Get.toNamed] does,
  /// and returns what it pops with. Null when it can't: animations are off,
  /// the card is off screen, or no route goes by that name; the caller then
  /// opens the page as it would have. Tapped again while its page opens, it
  /// opens nothing more. [parameters] go into the page's name, as
  /// Get.toNamed puts them. With [moveContent] the card's content moves onto
  /// where the page marks it with a [VideoExpandContent], as a dynamic into
  /// its detail, rather than fading out as the page grows.
  Future<T?>? expand<T>(
    String page, {
    dynamic arguments,
    Map<String, String>? parameters,
    bool moveContent = false,
  }) {
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
      settings: RouteSettings(
        name: parameters == null
            ? page
            : Uri(path: page, queryParameters: parameters).toString(),
        arguments: arguments,
      ),
    );
    while (redirect.needRecheck()) {}
    final target = redirect.route;
    if (redirect.isUnknown || target == null) {
      return null;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Moving, the card's content is its picture: no cover of its own.
    final cover = moveContent ? null : _coverImage();
    // The page below is taken now, while the frame costs little: from the
    // next frame on the page grows over the card's rect, opaque, so the card
    // need not hide first.
    // The page under it is the card's, if that is the top one and covers the
    // pages under it.
    final below = ModalRoute.of(context);
    final route = VideoExpandRoute<T>(
      source: this,
      belowRoute: below != null && below.isCurrent && below.opaque
          ? below
          : null,
      cardImage: _cardImage(pixelRatio),
      cover: cover?.$1,
      coverFilter: cover?.$2,
      moveContent: moveContent,
      page: target.page,
      parameter: target.parameters,
      settings: redirect.settings,
      binding: target.binding,
      bindings: target.bindings,
      middlewares: target.middlewares,
    ).._takeBelow(_takePressedInPlace());
    final opened = navigator.push(route);
    _route = route;
    route.animation!.addStatusListener(_handleRouteStatus);
    route.completed.whenComplete(() => _shown(route));
    // A route spends its first frame offstage, so the card hides as the page
    // first shows, a frame on.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route)) {
        setState(() => _hidden = true);
        route._coverBelow();
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

  // The page the card lies on, taken as a press holds still on the card:
  // drawing that picture is the opening's dearest work, a whole screen of
  // pixels, about 13 ms of a OnePlus 7 Pro's GPU at 427 MHz, which would
  // otherwise hold its first frame back. A finger stays down for a tenth of
  // a second or so, time enough to draw it before the tap.
  // One picture for the whole app, of the last press on a card's cover:
  // every press drops the one before, so a tap only ever finds its own.
  static _Pressed? _pressed;
  static VideoExpandSourceState? _pressedBy;
  static Timer? _pressedExpiry;
  Timer? _pressTimer;
  Offset? _pressAt;
  double _pressSlop = kTouchSlop;
  ValueListenable<bool>? _scrolling;

  /// How long a press holds still before the page is taken: a finger that
  /// goes on to scroll has passed the touch slop by then, mostly.
  static const pressHold = Duration(milliseconds: 40);

  /// How long a picture taken on a press waits for its tap, which may wait
  /// for a request; the page could change by then.
  static const _pressedLife = Duration(milliseconds: 500);

  void _handlePointerDown(PointerDownEvent event) {
    _dropPressed();
    _pressTimer?.cancel();
    _pressTimer = null;
    _pressAt = null;
    _stopWatchingScroll();
    // Only a press on the cover, which opens the page: the card's own
    // buttons, as a like, lie beside it, and a card that cannot open its
    // page, as in multi-select, takes none.
    final cover = _coverRect;
    if (!widget.takesPressShot ||
        cover == null ||
        !cover.contains(event.position)) {
      return;
    }
    _pressAt = event.position;
    // The smallest slop a gesture around it moves on: the device's, or the
    // app's for horizontal swipes, as history's.
    _pressSlop = [
      kTouchSlop,
      ?MediaQuery.gestureSettingsOf(context).touchSlop,
      touchSlopH,
    ].reduce(math.min);
    // And should the list around it start to scroll first, it is no tap.
    _scrolling = Scrollable.maybeOf(context)?.position.isScrollingNotifier
      ?..addListener(_handleScrolling);
    _pressTimer = Timer(pressHold, _takeOnPress);
  }

  void _handleScrolling() {
    if (_scrolling?.value ?? false) {
      _endPress();
    }
  }

  void _stopWatchingScroll() {
    _scrolling?.removeListener(_handleScrolling);
    _scrolling = null;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pressAt case final at?
        when (event.position - at).distance > _pressSlop) {
      _endPress();
    }
  }

  // Lifted, the tap that follows takes what the press took.
  void _handlePointerUp(PointerUpEvent event) {
    _pressTimer?.cancel();
    _pressTimer = null;
    _pressAt = null;
    _stopWatchingScroll();
  }

  void _endPress() {
    _pressTimer?.cancel();
    _pressTimer = null;
    _pressAt = null;
    _stopWatchingScroll();
    if (identical(_pressedBy, this)) {
      _dropPressed();
    }
  }

  void _takeOnPress() {
    _pressTimer = null;
    final route = ModalRoute.of(context);
    if (!mounted ||
        _route != null ||
        route == null ||
        !route.isCurrent ||
        !route.opaque ||
        !VideoExpand.enabled(context)) {
      return;
    }
    final below = VideoExpandRoute._pictureOf(route);
    final card = _cardRect;
    final layers = VideoExpandRoute._layersOf(route, this);
    if (below == null || card == null || layers == null) {
      below?.image.dispose();
      return;
    }
    _dropPressed();
    _pressed = (route: route, card: card, layers: layers, below: below);
    _pressedBy = this;
    _pressedExpiry = Timer(_pressedLife, _dropPressed);
    // The picture is drawn as the next frame goes to the GPU, not before:
    // a frame now has it drawn while the finger is still down.
    SchedulerBinding.instance.scheduleForcedFrame();
  }

  static _Pressed? _takePressed() {
    final pressed = _pressed;
    _pressed = null;
    _pressedBy = null;
    _pressedExpiry?.cancel();
    _pressedExpiry = null;
    return pressed;
  }

  // What this card's press took, if the card still stands where it did
  // then: a card that opens after a request may see its list scrolled
  // meanwhile. Whether the page itself is as it was, the route checks.
  _Pressed? _takePressedInPlace() {
    if (!identical(_pressedBy, this)) {
      return null;
    }
    final pressed = _takePressed()!;
    if (pressed.card == _cardRect) {
      return pressed;
    }
    pressed.below.image.dispose();
    return null;
  }

  static void _dropPressed() {
    _takePressed()?.below.image.dispose();
  }

  /// Whether a press holds a picture of the page, for tests.
  @visibleForTesting
  static bool get debugHoldsPressShot => _pressed != null;

  // The card as built, kept over the rebuilds that only the route or the
  // hiding cause: the route stopping being current rebuilds this, which
  // looked it up, and would build the card again as its page opens. The
  // card's own lookups go through its own element, which still rebuilds it.
  late Widget _card = _SourceCard(this);

  @override
  void didUpdateWidget(VideoExpandSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    _card = _SourceCard(this);
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    _pressTimer?.cancel();
    _stopWatchingScroll();
    if (identical(_pressedBy, this)) {
      _dropPressed();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hidden, it takes no taps either: as its page returns, the route lets
    // taps through to the page below, which would open it again.
    return IgnorePointer(
      ignoring: _hidden,
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: (_) => _endPress(),
        child: Opacity(
          opacity: _hidden ? 0 : 1,
          child: RepaintBoundary(
            key: _cardKey,
            child: _card,
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard(this.source);

  final VideoExpandSourceState source;

  @override
  Widget build(BuildContext context) => source.widget.builder(context, source);
}

/// The video page's route, opened out of a [VideoExpandSource]: the page
/// grows out of the card, the cover into the player, which the page marks
/// with a [VideoExpandTarget].
class VideoExpandRoute<T> extends GetPageRoute<T> {
  VideoExpandRoute({
    required this.source,
    this.belowRoute,
    required this.cardImage,
    required this.cover,
    this.coverFilter,
    this.moveContent = false,
    super.settings,
    super.page,
    super.parameter,
    super.binding,
    super.bindings,
    super.middlewares,
  });

  final VideoExpandSourceState source;

  /// Whether the page has landed, its opening done. What it builds late
  /// waits for this, so that the opening's frames stay light.
  ValueListenable<bool> get landed => _landed;
  final _landed = ValueNotifier(false);

  /// A picture of the card and its cover, taken as it opened. The route
  /// owns them.
  final ui.Image? cardImage;
  final ui.Image? cover;

  /// The color the card blends into its cover, which the cover keeps.
  final ColorFilter? coverFilter;

  /// Whether the card's content moves onto the page's, which it marks with
  /// a [VideoExpandContent].
  final bool moveContent;

  // Where the page lays the card's content out.
  VideoExpandContentState? _content;

  /// The route right under this one, the card's, when it covers the ones
  /// under it: only then does a picture of it stand in for all of them.
  final ModalRoute<dynamic>? belowRoute;

  // The page the card stands on, as it stood when the card was tapped, drawn
  // under the scrim in its place, as GlassMorphButton's route does: the
  // navigator
  // leaves the page itself unpainted, which would otherwise draw again every
  // frame, its glass and all, there being no raster cache to keep it. It
  // covers it from the page's first frame on screen, the second.
  _Below? _below;
  bool _covering = false;

  // Whether it returns with no card to return into, over the page below
  // drawn as it is.
  bool _returnsPlain = false;

  /// Whether the route holds a picture of the page below.
  @visibleForTesting
  bool get debugHoldsBelow => _below != null;

  // Whether that picture was taken as the press held on the card.
  bool _belowTakenOnPress = false;

  /// Whether the picture of the page below was taken as the press held.
  @visibleForTesting
  bool get debugBelowTakenOnPress => _belowTakenOnPress;

  /// The page's player, where the cover grows into.
  VideoExpandTargetState? _target;

  /// The page's own background, as its player reads it under the page's
  /// theme: the video page may be dark in a light app.
  Color? _pageColor;

  @visibleForTesting
  Color? get debugPageColor => _pageColor;

  /// Whether the cover over the player has been let go, the video shown or
  /// given up on: it then fades back in over the video as the page returns,
  /// and a player built again shows it no more.
  bool _coverGone = false;

  /// Lets the cover over the player go, should the video never say it has
  /// shown: set as the page first holds it, so that a player built again
  /// meanwhile holds it no longer.
  Timer? _coverTimer;

  /// Whether the cover stands over the player, from when the page has
  /// opened until it has faded out, and how far it shows.
  final _coverShowing = ValueNotifier(false);
  AnimationController? _coverOpacityController;
  AnimationController get _coverOpacity => _coverOpacityController ??=
      AnimationController(vsync: navigator!, duration: _coverFade, value: 1);
  bool get _coverFaded => _coverOpacity.isDismissed;

  void _letCoverGo() {
    if (_coverGone) {
      return;
    }
    _coverGone = true;
    _coverTimer?.cancel();
    _coverOpacity.reverse().whenComplete(() => _coverShowing.value = false);
  }

  /// The route [context] is in, if a card opened it.
  static VideoExpandRoute<dynamic>? of(BuildContext context) =>
      switch (ModalRoute.of(context)) {
        final VideoExpandRoute<dynamic> route => route,
        _ => null,
      };

  @override
  void install() {
    super.install();
    // After TransitionRoute's own, which lets the page below show as the
    // route animates.
    animation!.addStatusListener(_keepBelowCovered);
    // The controller's own, not [animation]'s: as the route first builds,
    // offstage for the heroes to measure, [animation] stands completed.
    controller!.addStatusListener(_handleLanded);
  }

  void _handleLanded(AnimationStatus status) {
    _landed.value = status.isCompleted;
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    // A page over this one: the picture, the screen's size in the device's
    // pixels, would take its memory up for as long as both are open, one for
    // each page opened on.
    if (nextRoute != null) {
      _covering = false;
      _dropBelow();
    }
  }

  @override
  void dispose() {
    cardImage?.dispose();
    cover?.dispose();
    _coverTimer?.cancel();
    _coverShowing.dispose();
    _landed.dispose();
    _coverOpacityController?.dispose();
    _below?.image.dispose();
    _below = null;
    super.dispose();
  }

  // The navigator's size: the picture of the page below holds only while it
  // stays as it was taken, as a turned screen lays the page out anew.
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
    switch (status) {
      // Opened, the route keeps the picture for its return while it is on
      // top: taking it again would have the navigator draw the page below,
      // its glass and all, on the return's first frames, and then draw it
      // once more into the picture. A page opened over this one lets it go
      // (didChangeNext), so only the top page holds one.
      // Returning without one, it is taken again, as it stands now, once it
      // has drawn a frame on: the navigator draws it while the route returns.
      case AnimationStatus.reverse when _below == null && !_returnsPlain:
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (_below != null ||
              _returnsPlain ||
              animation?.status != AnimationStatus.reverse) {
            return;
          }
          _takeBelow(null);
          _coverBelow();
        });
      case AnimationStatus.forward:
        _returnsPlain = false;
      default:
    }
    if (_below == null ||
        !_covering ||
        !status.isAnimating ||
        overlayEntries.isEmpty) {
      return;
    }
    if (_screen != _below!.screen) {
      _dropBelow();
    } else {
      overlayEntries.first.opaque = true;
    }
  }

  /// Takes the page below, if it is the page right under this one and
  /// covers the pages under it, before the route is pushed: [pressed], taken
  /// as the press held on the card, when it still stands as then.
  void _takeBelow(_Pressed? pressed) {
    final below = belowRoute;
    if (below == null) {
      pressed?.below.image.dispose();
      return;
    }
    if (pressed != null) {
      final now = _where(below);
      // Nothing painted on the page since, or moved: what a frame changed
      // there, the picture would show as it was.
      if (identical(pressed.route, below) &&
          now != null &&
          now.rect == pressed.below.rect &&
          now.screen == pressed.below.screen &&
          listEquals(_layersOf(below, source), pressed.layers)) {
        _below = pressed.below;
        _belowTakenOnPress = true;
        return;
      }
      pressed.below.image.dispose();
    }
    _below = _pictureOf(below);
  }

  /// Where [route]'s page lies and the screen's size, if it can be drawn
  /// from a picture.
  static ({Rect rect, Size screen, double pixelRatio, OffsetLayer layer})?
  _where(ModalRoute<dynamic> route) {
    final boundary = route.subtreeContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer || !layer.supportsRasterization()) {
      return null;
    }
    final screen = switch (route.navigator?.context.findRenderObject()) {
      final RenderBox box when box.hasSize => box.size,
      _ => null,
    };
    final media = route.subtreeContext!
        .getInheritedWidgetOfExactType<MediaQuery>()
        ?.data;
    // A page with the keyboard up is laid out again as it goes: a picture
    // would keep the room it made for the keyboard. It draws as it is.
    if (screen == null || media == null || media.viewInsets != .zero) {
      return null;
    }
    return (
      rect: boundary.localToGlobal(Offset.zero) & boundary.size,
      screen: screen,
      pixelRatio: media.devicePixelRatio,
      layer: layer,
    );
  }

  /// What [route]'s page composited last, as far as a picture of it shows:
  /// each layer with what it draws, where it lies and how it clips, but for
  /// [source]'s card. Painted again, a layer draws a new picture; scrolled,
  /// it lies elsewhere.
  static List<Object?>? _layersOf(
    ModalRoute<dynamic> route,
    VideoExpandSourceState source,
  ) {
    final boundary = route.subtreeContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.attached) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    final root = boundary.layer;
    if (root == null) {
      return null;
    }
    // The card's own layers count as one: its ink is all a press paints
    // there, and the page covers the card from its first frame.
    final card = switch (source._cardKey.currentContext?.findRenderObject()) {
      // ignore: invalid_use_of_protected_member
      final RenderRepaintBoundary boundary => boundary.layer,
      _ => null,
    };
    final layers = <Object?>[];
    void visit(Layer layer) {
      layers.add(layer);
      if (identical(layer, card)) {
        layers.add((layer as OffsetLayer).offset);
        return;
      }
      switch (layer) {
        case PictureLayer(:final picture):
          layers.add(picture);
        case TextureLayer(:final textureId, :final rect):
          layers
            ..add(textureId)
            ..add(rect);
        // Before OffsetLayer, which they extend.
        case TransformLayer(:final transform, :final offset):
          layers
            ..add(transform?.clone())
            ..add(offset);
        case OpacityLayer(:final alpha, :final offset):
          layers
            ..add(alpha)
            ..add(offset);
        case OffsetLayer(:final offset):
          layers.add(offset);
        case ClipRectLayer(:final clipRect):
          layers.add(clipRect);
        case ClipRRectLayer(:final clipRRect):
          layers.add(clipRRect);
        case ClipRSuperellipseLayer(:final clipRSuperellipse):
          layers.add(clipRSuperellipse);
        case ClipPathLayer(:final clipPath):
          layers.add(clipPath);
        default:
          // Glass, which its pane sets in place as it paints.
          if (liquidGlassPaintCount(layer) case final paints?) {
            layers.add(paints);
          }
      }
      if (layer is ContainerLayer) {
        for (Layer? child = layer.firstChild; child != null;) {
          visit(child);
          child = child.nextSibling;
        }
      }
    }

    visit(root);
    return layers;
  }

  /// A picture of [route]'s page, as last composited: a tap's ink marks it
  /// to paint again.
  static _Below? _pictureOf(ModalRoute<dynamic> route) {
    final where = _where(route);
    if (where == null) {
      return null;
    }
    return (
      image: where.layer.toImageSync(
        Offset.zero & where.rect.size,
        pixelRatio: where.pixelRatio,
      ),
      rect: where.rect,
      screen: where.screen,
    );
  }

  /// Draws the page below from its picture from now on: from the page's
  /// first frame on screen, its first being offstage, which would leave
  /// nothing drawn.
  void _coverBelow() {
    _covering = true;
    if (animation case final animation?) {
      _keepBelowCovered(animation.status);
    }
  }

  /// Lets the page below draw itself again, as a page returning with no card
  /// to return into fades out over it, the card gone from it.
  void _uncoverBelow() {
    _returnsPlain = true;
    _covering = false;
    _dropBelow();
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

/// A picture of the page under the opening one, and where it stands on
/// screen. [screen] is the navigator's size as it was taken.
typedef _Below = ({ui.Image image, Rect rect, Size screen});

/// A picture of the page a card lies on, taken as a press held on the card.
typedef _Pressed = ({
  ModalRoute<dynamic> route,
  Rect card,
  List<Object?> layers,
  _Below below,
});

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
        if (_returnsPlain) {
          widget.route._uncoverBelow();
        }
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
          content: route.moveContent
              ? route._content?.context.findRenderObject() as RenderBox?
              : null,
          contentShown: route._content?._showsTop ?? true,
          moveContent: route.moveContent,
          videoShown: route._coverGone,
          radius: source.widget.radius,
          coverRadius: source.widget.coverRadius,
          cardColor: source.widget.color,
          pageColor:
              route._pageColor ?? Theme.of(context).scaffoldBackgroundColor,
          topPadding: MediaQuery.paddingOf(context).top,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          cardImage: route.cardImage,
          cover: route.cover,
          coverFilter: route.coverFilter,
          below: route._fittingBelow,
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
    required this.content,
    required this.contentShown,
    required this.moveContent,
    required this.videoShown,
    required this.radius,
    required this.coverRadius,
    required this.cardColor,
    required this.pageColor,
    required this.topPadding,
    required this.devicePixelRatio,
    required this.cardImage,
    required this.cover,
    required this.coverFilter,
    required this.below,
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

  /// Where the page lays the card's content out, which the card's picture
  /// moves onto when it does.
  final RenderBox? content;

  /// Whether the top of the page's content stands within what its scroll
  /// view shows.
  final bool contentShown;
  final bool moveContent;
  final bool videoShown;
  final double radius;
  final BorderRadius coverRadius;
  final Color cardColor;
  final Color pageColor;
  final double topPadding;
  final double devicePixelRatio;
  final ui.Image? cardImage;
  final ui.Image? cover;
  final ColorFilter? coverFilter;

  /// The page under this one, drawn in its place while it animates.
  final _Below? below;

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

  // The page as it stood as it first showed, or as it set off back, drawn
  // while it moves, as GlassMorphButton's page is: drawn live, the page's
  // glass captured what lies behind each pane again every frame, which the
  // GPU held the phone's frames back on (9 passes a frame on a dynamic's
  // detail). Taken a frame after the page was drawn live and whole, under the
  // page below's picture, so that its glass has caught all that lies behind
  // it; with no such picture to hide it under, the page draws live as it
  // moves. At rest the page draws itself.
  ui.Image? _pageShot;
  Size? _pageShotSize;
  // Whether the page was drawn live and whole the frame before, its glass
  // having caught all that lies behind each pane: at rest, or primed.
  bool _pageLive = false;
  // A page holding what cannot be drawn into a picture, as a playing video.
  bool _pageUnsnappable = false;

  void _dropPageShot() {
    _pageShot?.dispose();
    _pageShot = null;
  }

  // Kept from the opening into a return that cuts it short, the page as it
  // stood: a return from rest finds none, the page having drawn itself.
  bool get _holdsPageShot => _pageShot != null && _pageShotSize == size;

  ui.Image? _pageShotOf(RenderBox page) {
    if (_holdsPageShot) {
      return _pageShot;
    }
    _dropPageShot();
    if (_pageUnsnappable || !_pageLive) {
      return null;
    }
    final layer = OffsetLayer();
    // As SnapshotWidget paints its child to take it.
    PaintingContext(layer, Offset.zero & size)
      ..paintChild(page, Offset.zero)
      // ignore: invalid_use_of_protected_member
      ..stopRecordingIfNeeded();
    if (!layer.supportsRasterization()) {
      layer.dispose();
      _pageUnsnappable = true;
      return null;
    }
    _pageShot = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _config!.devicePixelRatio,
    );
    layer.dispose();
    _pageShotSize = size;
    return _pageShot;
  }

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
    _dropPageShot();
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
      _dropPageShot();
      _pageUnsnappable = false;
      context.paintChild(page, offset);
      _pageLive = true;
      return;
    }
    final screen = Offset.zero & size;
    void paintBelow() {
      if (config.below case final below?) {
        final image = below.image;
        context.canvas.drawImageRect(
          image,
          Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
          _local(below.rect).shift(offset),
          Paint()..filterQuality = FilterQuality.low,
        );
      }
    }

    if (config.returnsPlain) {
      paintBelow();
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
      paintBelow();
      _paintPlain(context, offset, page);
      return;
    }
    Rect? rectOf(RenderBox? box) => box != null && box.attached && box.hasSize
        ? MatrixUtils.transformRect(
            box.getTransformTo(this),
            Offset.zero & box.size,
          )
        : null;
    final player = rectOf(config.player);
    final Rect? contentTo = switch (rectOf(config.content)) {
      _ when !config.moveContent => null,
      // Until the page has laid it out, under the page's bar.
      null => Rect.fromLTWH(
        card.left,
        config.topPadding + kToolbarHeight,
        card.width,
        card.height,
      ),
      // Scrolled off the page, as to its comments: it returns fading
      // through instead, its content not flying in from out of sight.
      final _ when !config.contentShown => null,
      final rect => rect,
    };
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
      contentTo: contentTo,
    );
    // The page first shows: before its picture is taken, it is drawn live
    // once, whole and under the page below's picture, which hides it, so that
    // its glass catches all that lies behind each pane, the parts the
    // container does not show yet too. The container keeps its fill on this
    // frame, the page barely begun to fade in.
    final priming =
        frame.pageOpacity > 0 &&
        config.below != null &&
        !_pageUnsnappable &&
        !_pageLive &&
        !_holdsPageShot;
    if (priming) {
      context.paintChild(page, offset);
    }
    paintBelow();
    // After the page, should it have been drawn: it ends the canvas before it.
    final canvas = context.canvas;
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
    // Once the page shows, its own background covers the fill: the card has
    // faded out by then, both ways. A pass over the screen the GPU, which
    // holds the phone's frames back, is spared.
    if (frame.pageOpacity == 0 || priming) {
      canvas.drawRRect(
        rrect.shift(offset),
        Paint()
          ..color = Color.lerp(
            config.cardColor,
            config.pageColor,
            1 - frame.cardOpacity,
          )!,
      );
    }
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
    if (frame.pageOpacity > 0 && !priming) {
      final shot = _pageShotOf(page);
      _clip.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        frame.rect,
        rrect,
        (context, offset) {
          if (shot != null) {
            context.canvas.drawImageRect(
              shot,
              Offset.zero & Size(shot.width.toDouble(), shot.height.toDouble()),
              (Offset.zero & size).shift(offset),
              Paint()..filterQuality = FilterQuality.low,
            );
          } else {
            context.paintChild(page, offset);
          }
          // The page fades in over the container's fill, all the page's
          // color by now, as the card has faded out: so a veil of that color
          // lifting off it looks the same as the page fading, without
          // drawing the page offscreen every frame. The GPU, not the
          // threads, held the phone's frames back.
          if (frame.pageOpacity < 1) {
            context.canvas.drawRect(
              frame.rect.shift(offset),
              Paint()
                ..color = config.pageColor.withValues(
                  alpha: config.pageColor.a * (1 - frame.pageOpacity),
                ),
            );
          }
        },
        oldLayer: _clip.layer,
      );
      // Drawn live here, it was clipped: its glass caught only what the
      // container showed, and no picture is taken of it.
      _pageLive = false;
    } else {
      _clip.layer = null;
      _pageLive = priming;
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
        config.coverFilter,
      );
    }
    // The card's content over the page, crossing into the page's own as it
    // lands, within the container.
    if ((config.cardImage, frame.content) case (final image?, final at?)
        when frame.contentOpacity > 0) {
      context.canvas
        ..save()
        ..clipRRect(rrect.shift(offset))
        ..drawImageRect(
          image,
          Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
          at.shift(offset),
          Paint()
            ..filterQuality = FilterQuality.low
            ..color = Color.fromRGBO(0, 0, 0, frame.contentOpacity),
        )
        ..restore();
    }
  }

  // The page fading in or out over the screen, a little shrunk, when there
  // is no card to grow out of or return into.
  void _paintPlain(PaintingContext context, Offset offset, RenderBox page) {
    // Drawn live here, the page as it is.
    _dropPageShot();
    _pageLive = true;
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

  // While it moves, the page is drawn only where it has grown to, or faded,
  // and the page below from a picture: a tap reaches neither, rather than
  // the page's controls where they are not yet seen.
  @override
  bool hitTestSelf(Offset position) => _config!.animating;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      !_config!.animating && super.hitTestChildren(result, position: position);
}

/// The cover [image] fitted to cover [rect], cropped to it with [radius],
/// through the card's [filter].
void _paintCover(
  Canvas canvas,
  ui.Image image,
  Rect rect,
  BorderRadius radius,
  double opacity,
  ColorFilter? filter,
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
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..colorFilter = filter,
    )
    ..restore();
}

/// Marks the video page's player, which the cover of the card it opened
/// from grows into, and holds the cover there until the video's first frame
/// shows: [watchVideo] calls back once it has, and returns what stops it
/// watching. It draws the cover under the player, before the player is
/// built; the player draws it over its video with a [VideoExpandCover]. On a
/// page no card opened it is an empty box.
class VideoExpandTarget extends StatefulWidget {
  const VideoExpandTarget({super.key, required this.watchVideo});

  final VoidCallback Function(VoidCallback shown) watchVideo;

  @override
  State<VideoExpandTarget> createState() => VideoExpandTargetState();
}

class VideoExpandTargetState extends State<VideoExpandTarget> {
  VideoExpandRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  VoidCallback? _stopWatching;
  bool _videoShown = false;
  bool _opened = false;

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
    // Built again once the cover was let go, as the player is in another
    // layout after the screen turns: it stays gone.
    if (route._coverGone) {
      return;
    }
    _routeAnimation!.addStatusListener(_handleRouteStatus);
    _stopWatching ??= widget.watchVideo(_handleVideoShown);
    // Built after the page had opened, it holds the cover no longer than
    // one built as it opened would. Not as it builds, as the cover shows in
    // the player too.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route)) {
        _handleRouteStatus(route.animation!.status);
      }
    });
  }

  void _handleRouteStatus(AnimationStatus status) {
    final route = _route!;
    _opened = status.isCompleted;
    // While the page moves, its route draws the cover.
    route._coverShowing.value = _opened && !route._coverFaded;
    if (_opened) {
      _letGoOnceShown();
    }
  }

  void _handleVideoShown() {
    _stopWatching?.call();
    _stopWatching = () {};
    if (mounted) {
      _videoShown = true;
      _letGoOnceShown();
    }
  }

  void _letGoOnceShown() {
    final route = _route!;
    if (!_opened || route._coverGone) {
      return;
    }
    if (_videoShown) {
      route._letCoverGo();
    } else {
      // Not past this, should the video never say it has shown, though no
      // player holds the cover then, as in picture in picture.
      route._coverTimer ??= Timer(_coverHoldAtMost, route._letCoverGo);
    }
  }

  @override
  void dispose() {
    _stopWatching?.call();
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    if (identical(_route?._target, this)) {
      _route!._target = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _route?._pageColor = Theme.of(context).scaffoldBackgroundColor;
    return const SizedBox.expand(child: VideoExpandCover());
  }
}

/// The cover of the card the page grew out of, held over the player until
/// the video shows: over the video and under the player's controls, where
/// the player lays it. Empty on a page no card opened.
class VideoExpandCover extends StatelessWidget {
  const VideoExpandCover({super.key});

  @override
  Widget build(BuildContext context) {
    final route = VideoExpandRoute.of(context);
    final cover = route?.cover;
    if (route == null || cover == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder(
      valueListenable: route._coverShowing,
      builder: (context, showing, _) => showing
          // Out of reach of taps, which go to the player.
          ? IgnorePointer(
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: _CoverPainter(
                    cover,
                    route.coverFilter,
                    route._coverOpacity,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.image, this.filter, this.opacity)
    : super(repaint: opacity);

  final ui.Image image;
  final ColorFilter? filter;
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
        filter,
      );
    }
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) =>
      !identical(oldDelegate.image, image) ||
      oldDelegate.filter != filter ||
      oldDelegate.opacity != opacity;
}

/// Where a page opened out of a card with its content moving lays that
/// content out, as a dynamic's detail its dynamic: the card's picture moves
/// onto it, its top edge onto this one's, and crosses into it as it lands.
class VideoExpandContent extends StatefulWidget {
  const VideoExpandContent({super.key, required this.child});

  final Widget child;

  @override
  State<VideoExpandContent> createState() => VideoExpandContentState();
}

class VideoExpandContentState extends State<VideoExpandContent> {
  VideoExpandRoute<dynamic>? _route;
  ScrollableState? _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context);
    final route = VideoExpandRoute.of(context);
    if (identical(route, _route)) {
      return;
    }
    _leave();
    _route = route?.._content = this;
  }

  @visibleForTesting
  bool get debugShowsTop => _showsTop;

  // Whether its top edge stands within what its scroll view shows: scrolled
  // under the page's bar, it is laid out still, but out of sight.
  bool get _showsTop {
    final box = context.findRenderObject();
    final view = _scrollable?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        view is! RenderBox ||
        !view.attached ||
        !view.hasSize) {
      return true;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final viewTop = view.localToGlobal(Offset.zero).dy;
    return top >= viewTop - 1 && top < viewTop + view.size.height;
  }

  void _leave() {
    if (identical(_route?._content, this)) {
      _route!._content = null;
    }
    _route = null;
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
