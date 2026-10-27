import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The last frames' UI and raster times, mean and worst, over [child], for
/// telling on a device what a change costs. Two lines of text that take no
/// taps.
class FrameStats extends StatefulWidget {
  const FrameStats({super.key, required this.child});

  final Widget child;

  static _FrameStatsState? _shown;

  /// Starts the count over, as before measuring what a change costs.
  static void reset() => _shown?._timings.clear();

  /// The frames counted so far, in milliseconds, or null while the overlay
  /// is off: for a debug command to read.
  static Map<String, num>? measure() => _shown?._measure();

  @override
  State<FrameStats> createState() => _FrameStatsState();
}

class _FrameStatsState extends State<FrameStats> {
  static const _frames = 120;
  final _timings = Queue<FrameTiming>();
  Timer? _refresh;
  String _text = '';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    VideoGlass.debugDescribing = true;
    FrameStats._shown = this;
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    VideoGlass.debugDescribing = false;
    if (identical(FrameStats._shown, this)) FrameStats._shown = null;
    _refresh?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _timings.addLast(timing);
      if (_timings.length > _frames) {
        _timings.removeFirst();
      }
    }
    // At most once a second: each update draws a frame of its own.
    _refresh ??= Timer(const Duration(seconds: 1), () {
      _refresh = null;
      if (mounted) {
        setState(() => _text = _describe());
      }
    });
  }

  Map<String, num>? _measure() {
    if (_timings.length < 2) return null;
    double ms(Duration duration) => duration.inMicroseconds / 1000;
    final ui = [for (final timing in _timings) ms(timing.buildDuration)];
    final raster = [for (final timing in _timings) ms(timing.rasterDuration)];
    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    double worst(List<double> values) => values.reduce((a, b) => a > b ? a : b);
    final span =
        _timings.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        _timings.first.timestampInMicroseconds(FramePhase.buildStart);
    return {
      'frames': _timings.length,
      'rasterMean': mean(raster),
      'rasterWorst': worst(raster),
      'uiMean': mean(ui),
      'uiWorst': worst(ui),
      'fps': span > 0 ? (_timings.length - 1) * 1e6 / span : 0,
    };
  }

  String _describe() {
    if (_timings.isEmpty) return '';
    double ms(Duration duration) => duration.inMicroseconds / 1000;
    final ui = [for (final timing in _timings) ms(timing.buildDuration)];
    final raster = [for (final timing in _timings) ms(timing.rasterDuration)];
    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    double worst(List<double> values) => values.reduce((a, b) => a > b ? a : b);
    final span =
        _timings.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        _timings.first.timestampInMicroseconds(FramePhase.buildStart);
    final fps = span > 0 ? (_timings.length - 1) * 1e6 / span : 0;
    String f(double value) => value.toStringAsFixed(1);
    return 'raster 平均 ${f(mean(raster))} / 最差 ${f(worst(raster))} ms\n'
        'UI 平均 ${f(mean(ui))} / 最差 ${f(worst(ui))} ms · '
        '${fps.toStringAsFixed(0)} fps · ${_timings.length} 帧';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        // Clear of the player's bars, lock and screenshot buttons.
        if (_text.isNotEmpty)
          Align(
            alignment: const Alignment(0, -0.45),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xB3000000),
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: VideoGlass.debugInfo,
                    builder: (context, glass, _) => Text(
                      glass.isEmpty ? _text : '$_text\n$glass',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.3,
                        fontFeatures: [FontFeature.tabularFigures()],
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
