import 'dart:io' show Platform;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/update.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

abstract final class Update {
  // 清单里的 versionCode 是 tag 的 +N，也就是安装包的 build 号
  static bool hasUpdate(
    UpdateManifest manifest, {
    int versionCode = BuildConfig.versionCode,
  }) => manifest.versionCode > versionCode;

  // 按设备的 ABI 顺序挑安装包，supportedAbis 里排前面的是设备首选
  static UpdateAsset? pickApk(
    List<UpdateAsset> assets,
    List<String> supportedAbis,
  ) {
    for (final abi in supportedAbis) {
      for (final asset in assets) {
        if (asset.abi == abi && asset.name.endsWith('.apk')) return asset;
      }
    }
    return null;
  }

  // 给了 ext 时只认这种格式
  static bool hasPackage(UpdateManifest manifest, {String? ext}) =>
      manifest.assets.any((i) => ext == null || i.format == ext);

  // 桌面端按格式给下载按钮，只给清单里有的格式；一个都没有时给 Github
  static List<Widget> formatButtons(
    UpdateManifest manifest,
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
        if (hasPackage(manifest, ext: ext)) downloadBtn(text, ext: ext),
    ];
    return buttons.isEmpty ? [downloadBtn('Github')] : buttons;
  }

  // 检查更新
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (kDebugMode) return;
    SmartDialog.dismiss();
    try {
      final res = await UpdateHttp.manifest();
      final UpdateManifest manifest;
      switch (res) {
        case Success(:final response):
          manifest = response;
        case Error():
          // 自动检查时不打扰，包括这个平台的包还在上传（404）
          if (!isAuto) res.toast();
          return;
        default:
          return;
      }
      if (!hasUpdate(manifest)) {
        if (!isAuto) {
          SmartDialog.showToast('已是最新版本');
        }
        return;
      }
      SmartDialog.show(
        animationType: SmartAnimationType.centerFade_otherSlide,
        builder: (context) {
          final colorScheme = ColorScheme.of(context);
          Widget downloadBtn(String text, {String? ext}) => TextButton(
            onPressed: () => onDownload(manifest, ext: ext),
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
                      manifest.tag,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(manifest.body),
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
              ...formatButtons(manifest, downloadBtn),
            ],
          );
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
    }
  }

  // 在浏览器里下载适用于当前系统的安装包。浏览器下载没法校验哈希，
  // 所以直连 GitHub，不走镜像
  static Future<void> onDownload(UpdateManifest manifest, {String? ext}) async {
    SmartDialog.dismiss();
    try {
      final UpdateAsset? asset;
      if (Platform.isAndroid) {
        asset = pickApk(
          manifest.assets,
          (await DeviceInfoPlugin().androidInfo).supportedAbis,
        );
      } else {
        asset = manifest.assets
            .where((i) => ext == null || i.format == ext)
            .firstOrNull;
      }
      if (asset == null) throw UnsupportedError('no package');
      PageUtils.launchURL(UpdateHttp.assetUrl(manifest, asset));
    } catch (e) {
      if (kDebugMode) debugPrint('download error: $e');
      PageUtils.launchURL('${Constants.sourceCodeUrl}/releases/latest');
    }
  }
}
