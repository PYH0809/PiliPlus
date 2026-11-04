import 'package:flutter/services.dart';

// AppInstaller.kt
enum InstallResult {
  started,
  // 没有安装未知应用的权限
  permission,
  // 不是本应用的安装包，或者解析不了
  invalid,
  // 签名和已安装的不同，系统不让覆盖安装
  signature,
  // 版本比已安装的低
  downgrade,
  failed,
}

abstract final class AppInstaller {
  static const _channel = MethodChannel('PiliPlus/installer');

  // 通道出错时按做不到算；Activity 销毁后通道会注销（MissingPluginException）
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // 打开「安装未知应用」设置页；打不开时返回 false
  static Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<InstallResult> install(String path) async {
    try {
      final res = await _channel.invokeMethod<String>('install', {
        'path': path,
      });
      return InstallResult.values.asNameMap()[res] ?? InstallResult.failed;
    } on PlatformException {
      return InstallResult.failed;
    } on MissingPluginException {
      return InstallResult.failed;
    }
  }
}
