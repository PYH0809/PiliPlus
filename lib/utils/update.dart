import 'dart:io' show Platform;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

abstract final class Update {
  // 本仓库的 tag 是 <版本号>+<build 号>，比 build 号；Release 的 created_at
  // 是目标提交的时间，不是发版时间。其他 tag 照旧比时间
  static bool hasUpdate(
    Map data, {
    int versionCode = BuildConfig.versionCode,
    int buildTime = BuildConfig.buildTime,
  }) {
    final match = RegExp(
      r'^[\d.]+\+(\d+)$',
    ).firstMatch(data['tag_name'] as String? ?? '');
    if (match != null) {
      return int.parse(match[1]!) > versionCode;
    }
    final int latest =
        DateTime.parse(data['created_at']).millisecondsSinceEpoch ~/ 1000;
    return buildTime < latest;
  }

  // 安装包名形如 PiliPlus_<平台>_<版本>...，os 取 Platform.operatingSystem；
  // 给了 ext 时只认这种格式
  static bool hasPackage(Map data, String os, {String? ext}) {
    final assets = data['assets'];
    return assets is List &&
        assets.any((i) {
          final name = i['name'] as String? ?? '';
          return name.contains('_${os}_') &&
              (ext == null || name.endsWith(ext));
        });
  }

  // 桌面端按格式给下载按钮，只给已经传上来的格式；一个都没有时给 Github，
  // 打开 Release 页面
  static List<Widget> formatButtons(
    Map data,
    Widget Function(String text, {String? ext}) downloadBtn, {
    String os = '',
  }) {
    os = os.isEmpty ? Platform.operatingSystem : os;
    final formats = switch (os) {
      'windows' => const [('zip', 'zip'), ('exe', 'exe')],
      'linux' => const [
        ('rpm', 'rpm'),
        ('deb', 'deb'),
        ('targz', 'tar.gz'),
        ('AppImage', 'AppImage'),
      ],
      _ => const <(String, String)>[],
    };
    final buttons = [
      for (final (text, ext) in formats)
        if (hasPackage(data, os, ext: ext)) downloadBtn(text, ext: ext),
    ];
    return buttons.isEmpty ? [downloadBtn('Github')] : buttons;
  }

  // 检查更新
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (kDebugMode) return;
    SmartDialog.dismiss();
    try {
      final res = await Request().get(
        Api.latestApp,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          extra: {'account': const NoAccount()},
        ),
      );
      // 读 /releases/latest，也就是发版时标成 Latest 的那个
      final data = res.data;
      if (data is! Map || data['tag_name'] == null) {
        if (!isAuto) {
          // 还没有发布的版本时是 404
          SmartDialog.showToast(
            res.statusCode == 404 ? '暂时没有可用的版本' : '检查更新失败，GitHub接口未返回数据，请检查网络',
          );
        }
        return;
      }
      if (!hasUpdate(data)) {
        if (!isAuto) {
          SmartDialog.showToast('已是最新版本');
        }
      } else if (!hasPackage(data, Platform.operatingSystem)) {
        // 安卓的包传完就发布，其他平台的包随后才补上，下次检查再提示
        if (!isAuto) {
          SmartDialog.showToast('新版本的安装包还在上传，请稍后再试');
        }
      } else {
        SmartDialog.show(
          animationType: SmartAnimationType.centerFade_otherSlide,
          builder: (context) {
            final colorScheme = ColorScheme.of(context);
            Widget downloadBtn(String text, {String? ext}) => TextButton(
              onPressed: () => onDownload(data, ext: ext),
              child: Text(text),
            );
            return AlertDialog(
              title: const Text('🎉 发现新版本 '),
              content: SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['tag_name']}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text('${data['body']}'),
                      TextButton(
                        onPressed: () => PageUtils.launchURL(
                          '${Constants.sourceCodeUrl}/commits/main',
                        ),
                        child: Text(
                          "点此查看完整更新(即commit)内容",
                          style: TextStyle(color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isAuto)
                  TextButton(
                    onPressed: () {
                      SmartDialog.dismiss();
                      GStorage.setting.put(SettingBoxKey.autoUpdate, false);
                    },
                    child: Text(
                      '不再提醒',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
                TextButton(
                  onPressed: SmartDialog.dismiss,
                  child: Text(
                    '取消',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
                ...formatButtons(data, downloadBtn),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
    }
  }

  // 下载适用于当前系统的安装包
  static Future<void> onDownload(Map data, {String? ext}) async {
    SmartDialog.dismiss();
    try {
      void download(String plat) {
        if (data['assets'].isNotEmpty) {
          for (Map<String, dynamic> i in data['assets']) {
            final String name = i['name'];
            if (name.contains(plat) &&
                (ext == null || ext.isEmpty ? true : name.endsWith(ext))) {
              PageUtils.launchURL(i['browser_download_url']);
              return;
            }
          }
          throw UnsupportedError('platform not found: $plat');
        }
      }

      if (Platform.isAndroid) {
        // 获取设备信息
        AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
        // [arm64-v8a]
        download(androidInfo.supportedAbis.first);
      } else {
        download(Platform.operatingSystem);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('download error: $e');
      PageUtils.launchURL('${Constants.sourceCodeUrl}/releases/latest');
    }
  }
}
