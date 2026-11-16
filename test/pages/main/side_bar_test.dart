import 'dart:io';

import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-side-bar-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.userInfo = await Hive.openBox('userInfo');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() => Get.put(AccountService()));

  tearDown(() async {
    Get.reset();
    await GStorage.setting.clear();
  });

  // MainApp sets useBottomNav from the window only without the side bar, so
  // the controller's own value is the one the side bar is drawn by.
  test('with 改用侧边栏 on, the main page starts without the bottom bar', () async {
    await GStorage.setting.put(SettingBoxKey.useSideBar, true);
    expect(MainController().useBottomNav, isFalse);
  });

  test('without it, the bottom bar is the default until MainApp lays out', () {
    expect(MainController().useBottomNav, isTrue);
  });
}
