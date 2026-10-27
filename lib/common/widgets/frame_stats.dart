import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The last frames' UI and raster times, mean and worst, over [child], for
/// telling on a device what a change costs. A corner line of text that takes
/// no taps.
class FrameStats extends StatefulWidget {
  const FrameStats({super.key, required this.child});

  final Widget child;

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
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
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
        if (_text.isNotEmpty)
          Positioned(
            left: 8,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
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
                  child: Text(
                    _text,
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
      ],
    );
  }
}
