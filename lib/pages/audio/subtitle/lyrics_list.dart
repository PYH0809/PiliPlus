import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_subtitle/subtitle_line.dart';
import 'package:PiliPlus/pages/audio/subtitle/subtitle_mixin.dart';
import 'package:PiliPlus/utils/subtitle_utils.dart';
import 'package:flutter/physics.dart'
    show SpringDescription, SpringSimulation, Tolerance;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Apple Music's lyrics, line by line, as Bilibili's subtitles time whole
/// lines. The numbers are Apple Music for Android's where they are known
/// and AMLL's (applemusic-like-lyrics) where not; only the numbers.
abstract final class Lyrics {
  static const fontSize = 34.0;
  static const lineHeight = 1.2;

  /// Latin text is drawn this much tighter, in ems; CJK as it is.
  static const latinTracking = -0.02;

  /// From the panel's sides: 32 from the screen's with the page's 20.
  static const inset = 12.0;
  static const gap = 20.0;

  /// The line in focus has its top this far down the list.
  static const anchor = 0.08;

  static const litAlpha = 0.94;
  static const dimAlpha = 0.18;
  static const browsingAlpha = 0.45;
  static const dimScale = 0.98;

  /// Each line away from the focus blurs this much more, up to [maxBlur].
  static const blurStep = 1.5;
  static const maxBlur = 6.0;

  static const light = Duration(milliseconds: 750);
  static const lightCurve = Cubic(0.25, 0.1, 0.25, 1);
  static const scaleSpring = SpringDescription(
    mass: 2,
    stiffness: 100,
    damping: 25,
  );

  static const moveCurve = Cubic(0.4, 0.1, 0, 1);

  /// How much later the rows below the focus set off, the 1st to the 4th;
  /// the rest go with the 4th.
  static const stagger = [25, 44, 56, 63];
  static const seekSpring = SpringDescription(
    mass: 0.9,
    stiffness: 90,
    damping: 15,
  );

  /// After a scroll by hand, the list goes back no sooner than this.
  static const snapIdle = Duration(milliseconds: 500);

  static const topFade = 0.07;
  static const bottomFade = 0.2775;

  static double blur(int distance) =>
      math.min(distance.abs() * blurStep, maxBlur);

  static final _cjk = RegExp(
    r'[　-〿぀-ヿ㐀-䶿一-鿿가-힯＀-￯]',
  );

  static TextStyle style(String text, double alpha) => TextStyle(
    fontSize: fontSize,
    fontWeight: .w700,
    height: lineHeight,
    letterSpacing: _cjk.hasMatch(text) ? 0 : latinTracking * fontSize,
    color: Colors.white.withValues(alpha: alpha),
  );

  // The interlude's dots.
  static const dot = 0.3 * fontSize;
  static const dotGap = 0.18 * fontSize;

  /// The room the dots take above the line they wait for.
  static const dotsRoom = dot + 0.8 * fontSize;
}

/// The lines, the one in focus [Lyrics.anchor] down the list. Following the
/// player, each move starts early enough to land as its line starts.
/// A scroll by hand dims the lines evenly and unblurs them, and the list goes
/// back at the next line change, once it has been still a moment and that
/// line shows.
class AudioSubtitleList extends StatefulWidget {
  const AudioSubtitleList({super.key, required this.controller});

  final AudioSubtitleMixin controller;

  @override
  State<AudioSubtitleList> createState() => _AudioSubtitleListState();
}

class _AudioSubtitleListState extends State<AudioSubtitleList>
    with TickerProviderStateMixin {
  late final AudioSubtitleMixin _controller = widget.controller;
  final _scrollController = ScrollController();
  final _listController = ListController();
  late final List<Worker> _workers;

  /// A move in time with the lines, and the moves that are not: seeks,
  /// returns from an interlude or a scroll by hand.
  late final _timed = AnimationController(vsync: this)
    ..addListener(_onTimedTick)
    ..addStatusListener((status) {
      if (status.isCompleted) _settle();
    });
  late final _spring = GlassSpring(this, 0)..addListener(_onSpringTick);
  double _from = 0;
  bool _syncing = false;

  /// Where the list heads, and whether that is in time with the lines.
  ({int index, bool dots}) _focus = (index: -1, dots: false);

  /// Notifies the rows below the focus while they lag behind it.
  final _stagger = _Notifier();

  /// Scrolled by hand, until the list goes back.
  final _browsing = ValueNotifier(false);
  bool _idle = false;
  Timer? _idleTimer;
  int _pointers = 0;
  bool _springNext = false;

  /// The player's position between its updates, while dots show.
  late final _clock = _MediaClock(this, _controller);

  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    _workers = [
      ever(_controller.subtitleFocus, _onFocus),
      ever(_controller.subtitleLines, (_) => _jumpAfterLayout()),
      ever(_controller.subtitleInterlude, (_) => _clock.update()),
      ever(_controller.subtitlePosition, (_) => _clock.update()),
      ever(_controller.subtitlePlaying, (_) => _clock.update()),
      ever(_controller.subtitleRate, (_) {
        _clock.update();
        _retime();
      }),
      ever(_controller.subtitleSeeks, (_) {
        _clock.seeked();
        _onSeeked();
      }),
      ever(_controller.subtitleBuffering, (_) => _clock.update()),
    ];
    _clock.update();
    _jumpAfterLayout();
  }

  @override
  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    _idleTimer?.cancel();
    _timed.dispose();
    _spring.dispose();
    _clock.dispose();
    _stagger.dispose();
    _browsing.dispose();
    _listController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<SubtitleLine> get _lines =>
      _controller.subtitleLines.value.dataOrNull ?? const [];

  /// How tall the dots' room above line [index] is now.
  double _room(int index) {
    if (_controller.subtitleInterlude.value?.next != index) return 0;
    return Lyrics.dotsRoom * _clock.room;
  }

  /// The scroll offset that rests [focus] at the anchor.
  double? _offsetOf(({int index, bool dots}) focus) {
    if (focus.index < 0 ||
        !_listController.isAttached ||
        !_scrollController.hasClients ||
        focus.index >= _listController.numberOfItems) {
      return null;
    }
    final position = _scrollController.position;
    // ignore: invalid_use_of_visible_for_testing_member
    final top = _listController.getOffsetToReveal(focus.index, 0);
    // The line's own top, inside the half of the gap above it.
    final room = focus.dots ? 0 : _room(focus.index) + Lyrics.gap / 2;
    return (top + room - _viewport * Lyrics.anchor).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  void _jumpTo(double offset) {
    if (!_scrollController.hasClients) return;
    _syncing = true;
    _scrollController.position.jumpTo(offset);
    _syncing = false;
  }

  void _stop() {
    _timed.stop();
    if (_scrollController.hasClients) {
      _syncing = true;
      _spring.jumpTo(_scrollController.offset);
      _syncing = false;
    }
    _stagger.ping();
  }

  void _onFocus(({int index, bool dots}) focus) {
    final previous = _focus;
    _focus = focus;
    _stagger.ping();
    if (_browsing.value) {
      if (_pointers == 0 && _idle && _shows(focus.index)) {
        _browsing.value = false;
        _springTo(focus);
      }
      return;
    }
    if (_pointers > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_offsetOf(focus) case final offset?) _jumpTo(offset);
      return;
    }
    final inTime =
        !_springNext &&
        !focus.dots &&
        !previous.dots &&
        previous.index >= 0 &&
        focus.index == previous.index + 1 &&
        focus.index < _lines.length;
    _springNext = false;
    if (inTime) {
      _moveTo(
        SubtitleUtils.moveTo(
          _lines,
          focus.index,
          rate: _controller.subtitleRate.value,
        ),
      );
    } else {
      _springTo(focus);
    }
  }

  bool _shows(int index) {
    if (!_listController.isAttached) return false;
    final range = _listController.visibleRange;
    return range != null && index >= range.$1 && index <= range.$2;
  }

  void _moveTo(Duration duration) {
    _stop();
    if (!_scrollController.hasClients) return;
    _from = _scrollController.offset;
    _timed
      ..duration = duration
      ..forward(from: 0);
  }

  void _onTimedTick() {
    if (_offsetOf(_focus) case final target?) {
      _jumpTo(
        _from + (target - _from) * Lyrics.moveCurve.transform(_timed.value),
      );
    }
    _stagger.ping();
  }

  /// A move in time with the lines, when the speed changes on the way:
  /// to land as its line starts at the new one.
  void _retime() {
    final index = _focus.index;
    if (!_timed.isAnimating || index < 0 || index >= _lines.length) return;
    final left =
        (_lines[index].from - _controller.subtitlePosition.value) *
        (1 / _controller.subtitleRate.value);
    final done = _timed.value;
    if (left <= Duration.zero || done >= 1) return;
    _timed
      ..duration = left * (1 / (1 - done))
      ..forward(from: done);
  }

  /// How far row [rows] below the focus lags behind it in a timed move.
  double lagOf(int rows) {
    if (rows <= 0 || !_timed.isAnimating) return 0;
    final target = _offsetOf(_focus);
    final total = _timed.duration;
    if (target == null || total == null) return 0;
    final delay =
        Lyrics.stagger[math.min(rows, Lyrics.stagger.length) - 1] /
        total.inMilliseconds;
    // By how far it has gone, as a move re-timed on the way starts over.
    double at(double done) => Lyrics.moveCurve.transform(done.clamp(0.0, 1.0));
    return (target - _from) * (at(_timed.value) - at(_timed.value - delay));
  }

  void _springTo(({int index, bool dots}) focus) {
    _timed.stop();
    final target = _offsetOf(focus);
    if (target == null || !_scrollController.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _jumpTo(target);
      return;
    }
    // At rest, it starts from where the list is.
    if (_spring.target == _spring.value) {
      _syncing = true;
      _spring.jumpTo(_scrollController.offset);
      _syncing = false;
    }
    _spring.springTo(target, Lyrics.seekSpring);
    _stagger.ping();
  }

  void _onSpringTick() {
    if (_syncing) return;
    // The extents ahead are estimates until laid out: follow them.
    final target = _offsetOf(_focus);
    if (target != null && (target - _spring.target).abs() > 0.5) {
      _spring.springTo(target, Lyrics.seekSpring);
    }
    _jumpTo(_spring.value);
    if (_spring.value == _spring.target) _settle();
  }

  /// Once a move ends, lands it where the lines turned out to be, as the
  /// lines it went past were laid out on the way. A few frames at most.
  void _settle([int tries = 3]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          tries == 0 ||
          _browsing.value ||
          _pointers > 0 ||
          _timed.isAnimating ||
          _spring.value != _spring.target) {
        return;
      }
      final offset = _offsetOf(_focus);
      if (offset != null && (offset - _scrollController.offset).abs() > 0.5) {
        _jumpTo(offset);
        _settle(tries - 1);
      }
    });
  }

  void _jumpAfterLayout() {
    _browsing.value = false;
    _focus = _controller.subtitleFocus.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stop();
      if (_offsetOf(_focus) case final offset?) _jumpTo(offset);
      _settle();
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (_syncing) return false;
    switch (notification) {
      case UserScrollNotification(:final direction) when direction != .idle:
        _idleTimer?.cancel();
        _idle = false;
        _browsing.value = true;
        // A mouse wheel puts no pointer down to stop the move.
        _stop();
      case ScrollEndNotification() when _browsing.value:
        _startIdle();
    }
    return false;
  }

  void _startIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(Lyrics.snapIdle, () => _idle = true);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers++;
    // Or the move's jumps would end the drag starting.
    _stop();
    // Held, it is not left alone.
    _idleTimer?.cancel();
    _idle = false;
  }

  void _onPointerUp(PointerEvent event) {
    _pointers--;
    if (_pointers > 0) return;
    if (!_browsing.value) {
      // A touch that did not scroll: on to where the list was going.
      _springTo(_focus);
    } else if (!(_scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value)) {
      // Let go without a scroll, which would end in its own time.
      _startIdle();
    }
  }

  /// A seek shows where it landed, though the list was scrolled by hand, and
  /// springs there, as its focus may have moved a line on or not at all.
  void _onSeeked() {
    if (_pointers > 0) return;
    _idleTimer?.cancel();
    _browsing.value = false;
    _springTo(_controller.subtitleFocus.value);
  }

  void _onTapLine(int index) {
    _idleTimer?.cancel();
    _browsing.value = false;
    _springNext = true;
    final before = _controller.subtitleFocus.value;
    _controller.seekToSubtitleLine(index);
    // The focus did not move, as the line was in it: come back to it.
    if (_controller.subtitleFocus.value == before) {
      _springNext = false;
      _springTo(before);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return switch (_controller.subtitleLines.value) {
        Loading() => const Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        Success(:final response) when response.isEmpty => Center(
          child: Text(
            '暂无字幕',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        Success(:final response) => _buildLines(response),
        Error(:final errMsg) => Center(
          child: TextButton(
            onPressed: _controller.retrySubtitle,
            child: Text(
              '${errMsg ?? '字幕加载失败'}，点击重试',
              textAlign: .center,
            ),
          ),
        ),
      };
    });
  }

  Widget _buildLines(List<SubtitleLine> lines) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.maxHeight;
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ShaderMask(
              blendMode: .dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: .topCenter,
                end: .bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, Lyrics.topFade, 1 - Lyrics.bottomFade, 1],
              ).createShader(bounds),
              child: SuperListView.builder(
                // A new list for other lines, as it keeps the extents it
                // measured.
                key: ObjectKey(lines),
                controller: _scrollController,
                listController: _listController,
                padding: .only(
                  top: math.max(0, _viewport * Lyrics.anchor - Lyrics.gap / 2),
                  bottom: _viewport * (1 - Lyrics.anchor),
                ),
                itemCount: lines.length,
                itemBuilder: (context, index) => _LyricLine(
                  key: ValueKey(index),
                  list: this,
                  index: index,
                  line: lines[index],
                  dots: SubtitleUtils.interludeBefore(lines, index) != null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Notifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The player's position between the updates it sends, as the dots of an
/// interlude move with it every frame. It only ticks while dots show and
/// move: through an interlude they show in, playing.
class _MediaClock extends ChangeNotifier {
  _MediaClock(TickerProvider vsync, this._controller) {
    _ticker = vsync.createTicker(_tick);
  }

  final AudioSubtitleMixin _controller;
  late final Ticker _ticker;
  Duration _now = .zero;
  Duration _base = .zero;
  Duration _baseAt = .zero;

  bool _playing = false;
  double _rate = 1;

  /// When the interlude showing came into view, by the player's clock, and
  /// which it is.
  Duration? _entered;
  ({int next, Duration start, Duration end})? _enteredFor;

  /// Off from where it was heading by more, the player sought.
  static const _seekJump = Duration(milliseconds: 500);

  Duration get position =>
      _base + (_playing ? (_now - _baseAt) * _rate : .zero);

  ({int next, Duration start, Duration end})? get interlude =>
      _controller.subtitleInterlude.value;

  /// Whether the dots show at all: not for an interlude entered with less
  /// than 910 ms left.
  bool get shows {
    final interlude = this.interlude;
    final entered = _entered;
    if (interlude == null || entered == null) return false;
    return interlude.end - entered >= const Duration(milliseconds: 910);
  }

  /// How far the dots' room is open, 0 to 1: open over 180 ms, shut as the
  /// dots go in their last 250 ms.
  double get room {
    if (!shows) return 0;
    final opened = _progress(position - _entered!, 180);
    final shut = _progress(
      position - (interlude!.end - const Duration(milliseconds: 250)),
      250,
    );
    return opened * (1 - shut);
  }

  /// After a seek, the dots come in again from where it landed.
  void seeked() {
    _enteredFor = null;
    update();
  }

  void update() {
    final expected = position;
    final interlude = this.interlude;
    _base = _controller.subtitlePosition.value;
    _playing =
        _controller.subtitlePlaying.value &&
        !_controller.subtitleBuffering.value;
    _rate = _controller.subtitleRate.value;
    if (interlude == null) {
      _entered = null;
      _enteredFor = null;
    } else if (interlude != _enteredFor ||
        (_base - expected).abs() > _seekJump) {
      // Another interlude, or a seek in this one: the dots come in again
      // from here.
      _entered = _base < interlude.start ? interlude.start : _base;
      _enteredFor = interlude;
    }
    if (!_playing || !shows) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      // Its time starts over with the ticker.
      _now = .zero;
      _ticker.start();
    }
    _baseAt = _now;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

double _progress(Duration time, int milliseconds) =>
    (time.inMicroseconds / (milliseconds * 1000)).clamp(0.0, 1.0);

class _LyricLine extends StatefulWidget {
  const _LyricLine({
    super.key,
    required this.list,
    required this.index,
    required this.line,
    required this.dots,
  });

  final _AudioSubtitleListState list;
  final int index;
  final SubtitleLine line;

  /// Whether an interlude comes before it, with dots in the room above it.
  final bool dots;

  @override
  State<_LyricLine> createState() => _LyricLineState();
}

class _LyricLineState extends State<_LyricLine> {
  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    final controller = list._controller;
    final index = widget.index;
    final text = widget.line.content;
    Widget child = Obx(() {
      final lit = controller.subtitleLine.value == index;
      final focus = controller.subtitleFocus.value.index;
      final playing = controller.subtitlePlaying.value;
      return ValueListenableBuilder(
        valueListenable: list._browsing,
        builder: (context, browsing, _) {
          final scale = lit || !playing ? 1.0 : Lyrics.dimScale;
          final alpha = lit
              ? Lyrics.litAlpha
              : browsing
              ? Lyrics.browsingAlpha
              : Lyrics.dimAlpha;
          final blur = lit || browsing ? 0.0 : Lyrics.blur(index - focus);
          return TweenAnimationBuilder<double>(
            tween: Tween(end: alpha),
            duration: Lyrics.light,
            curve: Lyrics.lightCurve,
            builder: (context, alpha, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: blur),
              duration: Lyrics.light,
              curve: Lyrics.lightCurve,
              builder: (context, blur, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: scale),
                duration: _SpringCurve.scale.duration,
                curve: _SpringCurve.scale,
                builder: (context, scale, _) => Transform.scale(
                  scale: scale,
                  alignment: .centerLeft,
                  child: ImageFiltered(
                    enabled: blur > 0.05,
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: blur,
                      sigmaY: blur,
                    ),
                    child: Text(
                      text,
                      textWidthBasis: .longestLine,
                      style: Lyrics.style(text, alpha),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
    child = InkWell(
      onTap: () => list._onTapLine(index),
      borderRadius: const .all(.circular(12)),
      child: Padding(
        padding: const .symmetric(
          horizontal: Lyrics.inset,
          vertical: Lyrics.gap / 2,
        ),
        child: Align(alignment: .centerLeft, child: child),
      ),
    );
    if (widget.dots) {
      child = Column(
        crossAxisAlignment: .stretch,
        children: [
          _InterludeDots(clock: list._clock, index: index),
          child,
        ],
      );
    }
    return AnimatedBuilder(
      animation: list._stagger,
      builder: (context, child) {
        final rows = index - list._focus.index;
        final lag = list.lagOf(rows);
        return lag == 0
            ? child!
            : Transform.translate(offset: Offset(0, lag), child: child);
      },
      child: RepaintBoundary(child: child),
    );
  }
}

/// [Lyrics.scaleSpring] from rest to rest, as a curve over the time it takes
/// to settle.
class _SpringCurve extends Curve {
  _SpringCurve(SpringDescription spring)
    : _simulation = SpringSimulation(spring, 0, 1, 0),
      duration = _settle(spring);

  static final scale = _SpringCurve(Lyrics.scaleSpring);

  final SpringSimulation _simulation;
  final Duration duration;

  static Duration _settle(SpringDescription spring) {
    final simulation = SpringSimulation(
      spring,
      0,
      1,
      0,
      tolerance: Tolerance.defaultTolerance,
    );
    var t = 0.0;
    while (!simulation.isDone(t) && t < 5) {
      t += 1 / 120;
    }
    return Duration(microseconds: (t * 1e6).round());
  }

  @override
  double transformInternal(double t) =>
      _simulation.x(t * duration.inMicroseconds / 1e6);
}

/// Three dots where the next line will be, through an interlude, as AMLL
/// draws them: fading in one after another, lit in turn as the pause goes,
/// breathing, then swelling and shrinking away as the line comes.
class _InterludeDots extends StatelessWidget {
  const _InterludeDots({required this.clock, required this.index});

  final _MediaClock clock;
  final int index;

  static const _lightCurve = Cubic(0.56, 0.01, 0.45, 1);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: clock,
      builder: (context, _) {
        final interlude = clock.interlude;
        if (interlude == null || interlude.next != index || !clock.shows) {
          return const SizedBox.shrink();
        }
        final position = clock.position;
        final entered = clock._entered!;
        final sinceEntered = position - entered;
        final short = interlude.end - entered < const Duration(seconds: 3);
        final exit = interlude.end - const Duration(milliseconds: 1000);
        final swell = _progress(position - exit, 750);
        final shrink = _progress(
          position - (exit + const Duration(milliseconds: 750)),
          250,
        );
        final breath = short
            ? 1.0
            : 1 +
                  0.125 *
                      (1 -
                          math.cos(
                            2 * math.pi * sinceEntered.inMicroseconds / 4e6,
                          ));
        final scale = shrink > 0
            ? 1.25 + (0.4 - 1.25) * shrink
            : breath + (1.25 - breath) * swell;
        final container = _progress(sinceEntered, 180) * (1 - shrink);
        final total = interlude.end - interlude.start + Lyrics.light;
        final third = total ~/ 3;
        return SizedBox(
          height: Lyrics.dotsRoom * clock.room,
          child: OverflowBox(
            alignment: .centerLeft,
            maxHeight: Lyrics.dotsRoom,
            child: Padding(
              padding: const .only(left: Lyrics.inset),
              child: Opacity(
                opacity: container,
                child: Transform.scale(
                  scale: scale,
                  alignment: .centerLeft,
                  child: Row(
                    mainAxisSize: .min,
                    spacing: Lyrics.dotGap,
                    children: List.generate(3, (k) {
                      final fadeIn = _progress(
                        sinceEntered - Duration(milliseconds: 80 * k),
                        750,
                      );
                      final lit = short
                          ? 1.0
                          : _lightCurve.transform(
                              _progress(
                                position - interlude.start - third * k,
                                third.inMilliseconds,
                              ),
                            );
                      return Opacity(
                        opacity: fadeIn * fadeIn * (0.2 + 0.7 * lit),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: .circle,
                          ),
                          child: SizedBox.square(dimension: Lyrics.dot),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
