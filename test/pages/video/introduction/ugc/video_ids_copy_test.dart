import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/stat.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _tag = 'video-ids';

class _Player extends Fake implements PlPlayerController {
  @override
  bool get enableSponsorBlock => false;
}

/// The video page, as much of it as the intro panel reads.
class _Video extends Fake implements VideoDetailController {
  @override
  final plPlayerController = _Player();

  @override
  String? videoUrl = 'https://example.com/video.mp4';

  @override
  bool isQuerying = false;

  @override
  final videoLabel = ''.obs;

  @override
  String bvid = 'BV1xx411c7mD';

  @override
  int aid = 170001;

  // Registered with Get, which starts and deletes what it holds.
  @override
  final onStart = InternalFinalCallback<void>(callback: () {});

  @override
  final onDelete = InternalFinalCallback<void>(callback: () {});
}

class _Ugc extends UgcIntroController {
  _Ugc() {
    videoDetail.value = VideoDetailData(
      bvid: 'BV1xx411c7mD',
      aid: 170001,
      title: '第一个视频',
      stat: VideoStat.fromJson({
        'view': 10,
        'like': 1,
        'coin': 1,
        'favorite': 1,
        'share': 1,
      }),
    );
  }

  // The details are already here: no requests, the panel open.
  @override
  // ignore: must_call_super
  void onInit() {
    expand = RxBool(true);
    hasLater = RxBool(false);
  }

  final _video = _Video();

  @override
  VideoDetailController get videoDetailCtr => _video;
}

void main() {
  late Directory tempDir;
  final copied = <String>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-video-ids-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    // Read on the way, it stores its default when unset: a write inside the
    // test that would leave the box unable to close.
    await GStorage.setting.put(SettingBoxKey.horizontalScreen, false);
    // Signed out, without the accounts box.
    MineController.anonymity = false.obs;
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('the ids copy what they show while the next video loads', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    final ugc = Get.put<UgcIntroController>(_Ugc(), tag: _tag);
    Get.put<VideoDetailController>(ugc.videoDetailCtr, tag: _tag);
    addTearDown(Get.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              UgcIntroPanel(
                heroTag: _tag,
                showAiBottomSheet: () {},
                showEpisodes: ({required type, episodeType}) {},
                onShowMemberPage: (_) {},
                isPortrait: true,
                isHorizontal: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Another video of the season starts: the page moves on before its
    // details arrive, so the panel still shows the first one.
    (ugc.videoDetailCtr as _Video)
      ..bvid = 'BV1Q541167Qg'
      ..aid = 2;

    await tester.tap(find.text('BV1xx411c7mD'));
    await tester.tap(find.text('av170001'));
    // Lets the toasts go.
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(copied, ['BV1xx411c7mD', 'av170001']);
  });
}
