import 'dart:ui' show FramePhase, FrameTiming;

import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// The frames' UI and raster times since [reset], for the debug commands to
/// tell on a device what a change costs. It draws nothing: it counts from
/// the first [reset] on.
abstract final class FrameStats {
  // Every frame since the last reset, up to a minute's at 120 Hz.
  static final _counted = <FrameTiming>[];
  static var _counting = false;

  /// Starts the count over, as before measuring what a change costs.
  static void reset() {
    _counted.clear();
    if (_counting) return;
    _counting = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    VideoGlass.debugDescribing = true;
    // The glass over a still video describes itself as it paints: paint it
    // once now, rather than wait for something else to.
    void repaint(RenderObject object) {
      object
        ..markNeedsPaint()
        ..visitChildren(repaint);
    }

    RendererBinding.instance.renderViews.forEach(repaint);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      if (_counted.length < 7200) _counted.add(timing);
    }
  }

  /// The frames counted so far, in milliseconds, or null before [reset].
  static Map<String, num>? measure() {
    final counted = _counted;
    if (counted.length < 2) return null;
    double ms(Duration duration) => duration.inMicroseconds / 1000;
    final ui = [for (final timing in counted) ms(timing.buildDuration)];
    final raster = [for (final timing in counted) ms(timing.rasterDuration)];
    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    double worst(List<double> values) => values.reduce((a, b) => a > b ? a : b);
    final span =
        counted.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        counted.first.timestampInMicroseconds(FramePhase.buildStart);
    // Frames that came later than one and a half of the usual interval:
    // what a viewer sees as a stutter. The raster time alone is no sign of
    // it, as on OpenGL ES it holds the wait for a free screen buffer too.
    final finishes = [
      for (final timing in counted)
        timing.timestampInMicroseconds(FramePhase.rasterFinish),
    ];
    final intervals = [
      for (var i = 1; i < finishes.length; i++) finishes[i] - finishes[i - 1],
    ]..sort();
    final usual = intervals.isEmpty ? 0 : intervals[intervals.length ~/ 2];
    final dropped = intervals.where((i) => i > usual * 1.5).length;
    // Frames whose raster ran past a 120, a 90 Hz frame, and two of them.
    int over(double limit) => raster.where((t) => t > limit).length;
    return {
      'frames': counted.length,
      'dropped': dropped,
      'over8': over(8.3),
      'over11': over(11.1),
      'over20': over(20),
      'rasterMean': mean(raster),
      'rasterWorst': worst(raster),
      'uiMean': mean(ui),
      'uiWorst': worst(ui),
      'fps': span > 0 ? (counted.length - 1) * 1e6 / span : 0,
    };
  }

  /// Each frame counted so far: when its raster finished, in microseconds,
  /// and its raster and UI times in milliseconds.
  static List<List<num>> log() => [
    for (final timing in _counted)
      [
        timing.timestampInMicroseconds(FramePhase.rasterFinish),
        timing.rasterDuration.inMicroseconds / 1000,
        timing.buildDuration.inMicroseconds / 1000,
      ],
  ];
}
