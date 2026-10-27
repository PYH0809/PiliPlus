import 'package:PiliPlus/models/common/enum_with_label.dart';

/// How the glass over the video draws, from the dearest to the cheapest.
enum VideoGlassMode with EnumWithLabel {
  /// A blur, then the glass shader bending it each frame.
  refract('折射'),

  /// The blur alone.
  frost('磨砂'),

  /// No filter at all: a thicker tint and its rim.
  tint('仅底色'),
  ;

  @override
  final String label;
  const VideoGlassMode(this.label);
}
