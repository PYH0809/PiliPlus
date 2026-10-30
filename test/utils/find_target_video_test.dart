import 'dart:io';

import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

VideoItem _video(int id, String codecs) => VideoItem(
  id: id,
  baseUrl: 'https://example.com/$id.m4s',
  codecs: codecs,
  quality: VideoQuality.fromCode(id),
);

FormatItem _format(int quality) =>
    FormatItem(quality: quality, codecs: ['avc1.640032', 'hev1.1.6.L150.90']);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-target-video-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  const codecs = [VideoDecodeFormatType.AVC, VideoDecodeFormatType.HEVC];

  test('picks the preferred quality the links carry', () {
    final videos = [_video(80, 'avc1.640032'), _video(64, 'avc1.640028')];
    final (quality, _, _, video) = VideoUtils.findTargetVideo(
      videos,
      64,
      [116, 80, 64, 32],
      [_format(116), _format(80), _format(64), _format(32)],
      codecs,
    );
    expect(quality, 64);
    expect(video.id, 64);
  });

  test('falls back to the nearest quality the links carry when an accepted '
      'one is missing from them, as when the request for the missing '
      'qualities failed', () {
    // 64 is accepted, but the first answer carried only 80 and 32.
    final videos = [_video(80, 'avc1.640032'), _video(32, 'avc1.64001F')];
    final (quality, _, _, video) = VideoUtils.findTargetVideo(
      videos,
      64,
      [116, 80, 64, 32],
      [_format(116), _format(80), _format(64), _format(32)],
      codecs,
    );
    expect(quality, 32);
    expect(video.id, 32);
  });
}
