import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/update.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/android/app_installer.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/update_download.dart';
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
      final apk = Platform.isAndroid
          ? pickApk(
              manifest.assets,
              (await DeviceInfoPlugin().androidInfo).supportedAbis,
            )
          : null;
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
            // 按钮放不下一行时竖着排，主按钮在最上面
            actionsOverflowDirection: VerticalDirection.up,
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
              if (apk != null) ...[
                downloadBtn('浏览器下载'),
                FilledButton(
                  onPressed: () => _downloadInApp(manifest, apk),
                  child: const Text('下载并安装'),
                ),
              ] else
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

  static void _downloadInApp(UpdateManifest manifest, UpdateAsset apk) {
    SmartDialog.dismiss();
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (_) => _DownloadDialog(manifest: manifest, apk: apk),
    );
  }
}

enum _Stage { downloading, failed, install }

// 应用内下载、校验并打开系统安装程序；关掉对话框就取消下载
class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.manifest, required this.apk});

  final UpdateManifest manifest;
  final UpdateAsset apk;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  UpdateDownloader? _downloader;
  _Stage _stage = .downloading;
  String _source = '';
  int _sourceIndex = 0;
  int _received = 0;
  String _message = '';
  File? _file;
  // 签名或版本对不上时再点安装也没用，不给按钮
  bool _canInstall = true;
  // 正在打开安装程序或者等设置页回来，按钮先不能点
  bool _installing = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _downloader?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  void _start() {
    _stage = .downloading;
    _sourceIndex = -1;
    _received = 0;
    _download();
  }

  Future<void> _download() async {
    final downloader = _downloader = UpdateDownloader(
      manifest: widget.manifest,
      asset: widget.apk,
      dir: '$tmpDirPath/update',
    );
    try {
      final file = await downloader.run(
        onSource: (source) {
          if (!mounted) return;
          setState(() {
            _source = source;
            _sourceIndex++;
            _received = 0;
          });
        },
        onProgress: (received, _) {
          if (mounted) setState(() => _received = received);
        },
      );
      if (file == null || !mounted) return;
      _file = file;
      // 在后台时系统可能拦下打开安装程序和设置页，等回到前台再装
      await _whenResumed();
      if (!mounted) return;
      await _install();
    } on UpdateDownloadException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = .failed;
        _message = '$e';
      });
    }
  }

  Future<void> _whenResumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == .resumed) return Future.value();
    final resumed = Completer<void>();
    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!resumed.isCompleted) resumed.complete();
      },
    );
    return resumed.future.whenComplete(() {
      _lifecycle?.dispose();
      _lifecycle = null;
    });
  }

  Future<void> _install() async {
    if (_installing) return;
    _installing = true;
    try {
      await _installOnce();
    } finally {
      _installing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _installOnce() async {
    final file = _file!;
    setState(() {
      _stage = .install;
      _message = '安装包已下载并校验通过，正在打开系统安装程序';
    });
    var res = await AppInstaller.install(file.path);
    if (res == .permission) {
      if (!mounted) return;
      setState(() => _message = '请在设置里允许 PiliPlus 安装应用，返回后会继续安装');
      final resumed = Completer<void>();
      _lifecycle?.dispose();
      _lifecycle = AppLifecycleListener(
        onResume: () {
          if (!resumed.isCompleted) resumed.complete();
        },
      );
      try {
        if (!await AppInstaller.openSettings()) {
          if (mounted) setState(() => _message = '无法打开「安装未知应用」设置，请到系统设置里允许');
          return;
        }
        await resumed.future;
      } finally {
        _lifecycle?.dispose();
        _lifecycle = null;
      }
      if (!mounted) return;
      if (!await AppInstaller.canInstall()) {
        if (mounted) setState(() => _message = '没有获得安装应用的权限，无法安装');
        return;
      }
      res = await AppInstaller.install(file.path);
    }
    if (!mounted) return;
    _canInstall = res != .signature && res != .downgrade;
    if (res == .invalid) {
      try {
        file.deleteSync();
      } catch (_) {}
      _file = null;
    }
    setState(
      () => _message = switch (res) {
        .started => '已打开系统安装程序。如果没有装上，可以点「安装」再试',
        .signature =>
          '安装包的签名和已安装的 PiliPlus 不同（比如现在装的是自己编译的版本），'
              '系统不允许覆盖安装。需要先卸载当前版本再安装；卸载会清除应用数据，'
              '也会删掉这里下好的安装包，可以先用「浏览器下载」把它存到手机上',
        .downgrade => '安装包的版本比已安装的低，系统不允许覆盖安装',
        .invalid => '安装包无法解析，已删除，请重新下载',
        .permission => '没有获得安装应用的权限，无法安装',
        .failed => '无法打开系统安装程序，请用浏览器下载',
      },
    );
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final total = widget.apk.size;
    final cancel = TextButton(
      onPressed: SmartDialog.dismiss,
      child: Text(
        _stage == .downloading ? '取消' : '关闭',
        style: TextStyle(color: colorScheme.outline),
      ),
    );
    final browser = TextButton(
      onPressed: () => Update.onDownload(widget.manifest),
      child: const Text('浏览器下载'),
    );
    return AlertDialog(
      title: Text(switch (_stage) {
        .downloading => '正在下载 ${widget.manifest.tag}',
        .failed => '下载失败',
        .install => '安装新版本',
      }),
      content: switch (_stage) {
        .downloading => Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            // 还在连下载源时没有进度，给不定进度条
            LinearProgressIndicator(
              value: _received > 0 && total > 0 ? _received / total : null,
            ),
            const SizedBox(height: 12),
            Text(
              '${_mb(_received)} / ${_mb(total)} MB · 来自 $_source',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        .failed => Text('所有下载源都失败了：\n$_message'),
        .install => Text(_message),
      },
      actionsOverflowDirection: VerticalDirection.up,
      actions: switch (_stage) {
        .downloading => [
          cancel,
          if (_sourceIndex < updateMirrors.length - 1)
            TextButton(
              onPressed: _downloader?.skip,
              child: const Text('换下载源'),
            ),
        ],
        .failed => [
          cancel,
          browser,
          FilledButton(
            onPressed: () => setState(_start),
            child: const Text('重试'),
          ),
        ],
        .install => [
          cancel,
          // 装不上时的后备，签名不符时也用它把安装包存到应用外面
          browser,
          if (_file == null)
            FilledButton(
              onPressed: () => setState(_start),
              child: const Text('重新下载'),
            )
          else if (_canInstall)
            FilledButton(
              onPressed: _installing ? null : _install,
              child: const Text('安装'),
            ),
        ],
      },
    );
  }
}
