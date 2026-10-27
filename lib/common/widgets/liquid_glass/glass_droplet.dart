// After FlClash's popup morph (https://github.com/chen08209/FlClash,
// lib/ui/popup.dart, GPL-3.0): a card of glass returning into its button as
// a drop, which menus and pages share.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

/// How long a card takes to return into its button.
const glassDropletReturn = Duration(milliseconds: 500);

/// [glassDropletReturn] in seconds.
final glassDropletReturnSeconds = glassDropletReturn.inMicroseconds / 1e6;

// iOS returns a card into its button as one drop of glass: the platter dips
// away, then shrinks into the button, which re-forms out of a droplet and
// rises past its place.
final _droplet = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 165, ratio: 0.8),
  0,
  1,
  0,
);

/// How far the card and its droplet flow into each other.
const glassDropletBlend = 28.0;

/// How much of its button a droplet takes, and how far from the button
/// toward the card it lies.
const glassDropletShare = 0.25;

/// How much of its button's shortest side a platter shrinks to.
const glassPlatterInControl = 0.41;

// Inside the button by then, the droplet settles into it.
const _dropletAbsorbed = Interval(0.6, 0.9, curve: Curves.easeInOut);

/// Rises to 1 at [peak] and back, as iOS's droplets overshoot and swell.
double glassRiseAndFall(double time, double peak, double sharpness) {
  if (time <= 0) {
    return 0;
  }
  final x = time / peak;
  return math.pow(x, sharpness) * math.exp(sharpness * (1 - x));
}

/// Where a card stands [time] seconds into its return into [anchor], its
/// button, from [from], rounded by [fromRadius]: the [platter] it shrinks
/// to, rounded by [radius], dips away and shrinks toward the button while a
/// [droplet] flows out of it and rises into the button, the two flowing
/// together by [blend] until the droplet has settled, [absorbed], in it.
/// [progress] runs from 0 to 1 on the way.
({
  Rect platter,
  double radius,
  Rect droplet,
  double blend,
  double progress,
  double absorbed,
})
glassDropletReturnAt({
  required Rect from,
  required double fromRadius,
  required Rect anchor,
  required double time,
}) {
  final fromDroplet = Rect.fromCenter(
    center: Offset.lerp(anchor.center, from.center, glassDropletShare)!,
    width: anchor.width * glassDropletShare,
    height: anchor.height * glassDropletShare,
  );
  // The spring still rings a little when the route ends; ease that out so
  // the droplet comes to rest on the button.
  final ringing =
      1 - Curves.easeIn.transform(((time - 0.4) / 0.1).clamp(0.0, 1.0));
  final progress = 1 + (_droplet.x(time) - 1) * ringing;
  final toCard = from.center.dy - anchor.center.dy;
  final away = toCard.sign;
  final dip =
      math.min(0.21 * toCard.abs(), 22.0) * glassRiseAndFall(time, 0.072, 2.4);
  final lift =
      math.min(0.25 * toCard.abs(), 19.0) * glassRiseAndFall(time, 0.176, 4.9);
  final scale = lerpDouble(
    1,
    glassPlatterInControl *
        anchor.shortestSide /
        math.max(from.width, from.height),
    progress,
  )!;
  final platter = Rect.fromCenter(
    center:
        Offset.lerp(from.center, anchor.center, progress)! +
        Offset(0, away * dip * ringing),
    width: math.max(0.0, from.width * scale),
    height: math.max(
      0.0,
      lerpDouble(from.height, from.width, progress)! * scale,
    ),
  );
  final radius = math.max(
    0.0,
    lerpDouble(fromRadius, from.width / 2, progress)! * scale,
  );
  final droplet = Rect.fromCenter(
    center:
        Offset.lerp(fromDroplet.center, anchor.center, progress)! -
        Offset(0, away * lift * ringing),
    width: lerpDouble(fromDroplet.width, anchor.width, progress)!,
    height: lerpDouble(fromDroplet.height, anchor.height, progress)!,
  );
  final absorbed = _dropletAbsorbed.transform(
    (time / glassDropletReturnSeconds).clamp(0.0, 1.0),
  );
  return (
    platter: platter,
    radius: radius,
    droplet: droplet,
    blend: glassDropletBlend * math.min(1.0, time / 0.05) * (1 - absorbed),
    progress: progress,
    absorbed: absorbed,
  );
}

/// Paints [shadows] for [rect], rounded by [radius], outside [outline] only:
/// a pane of goo casts none of its own, so its parts' shadows fall outside
/// it, as FlClash draws them.
void paintGlassShadowsOutside(
  Canvas canvas,
  Path outline,
  Rect rect,
  double radius,
  List<BoxShadow> shadows,
) {
  if (shadows.isEmpty) {
    return;
  }
  final reach = shadows.fold(
    0.0,
    (reach, shadow) =>
        math.max(reach, shadow.blurSigma * 3 + shadow.offset.distance),
  );
  canvas
    ..save()
    ..clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(outline.getBounds().expandToInclude(rect).inflate(reach))
        ..addPath(outline, Offset.zero),
    );
  for (final shadow in shadows) {
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        rect.shift(shadow.offset).inflate(shadow.spreadRadius),
        Radius.circular(radius),
      ),
      shadow.toPaint(),
    );
  }
  canvas.restore();
}
