import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/update.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/android/app_installer.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/update_download.dart';
import 'package:PiliPlus/utils/update_view.dart';
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

  // 用户在对话框里点过「跳过此版本」的版本，自动检查时不再提示，比它新的
  // 照常提示；从「关于」手动检查是用户自己要看，照常提示
  static bool isSkipped(
    UpdateManifest manifest, {
    required bool isAuto,
    required int skipped,
  }) => isAuto && manifest.versionCode <= skipped;

  // 这一版的提交：清单带了上一版的 tag 就比较两版，没有就打开这一版的
  // Release 页
  static String commitsUrl(UpdateManifest manifest) {
    final tag = Uri.encodeComponent(manifest.tag);
    if (manifest.previousTag case final previous?) {
      return '${Constants.sourceCodeUrl}/compare/'
          '${Uri.encodeComponent(previous)}...$tag';
    }
    return '${Constants.sourceCodeUrl}/releases/tag/$tag';
  }

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

  // 桌面端按格式给下载按钮，只给清单里有的格式，排在前面的是首选（填充、
  // 竖排时在最上面）；一个都没有时给「前往下载」，打开 Release 页面
  static List<Widget> formatButtons(
    UpdateManifest manifest,
    Widget Function(String text, {String? ext, bool primary}) downloadBtn, {
    String os = '',
  }) {
    os = os.isEmpty ? Platform.operatingSystem : os;
    final formats = switch (os) {
      'windows' => const [('安装版', 'exe'), ('便携版', 'zip')],
      'linux' => const [
        ('AppImage', 'AppImage'),
        ('deb', 'deb'),
        ('rpm', 'rpm'),
        ('tar.gz', 'tar.gz'),
      ],
      _ => const <(String, String)>[],
    };
    final available = [
      for (final (text, ext) in formats)
        if (hasPackage(manifest, ext: ext)) (text, ext),
    ];
    if (available.isEmpty) return [downloadBtn('前往下载', primary: true)];
    return [
      for (final (index, (text, ext)) in available.indexed)
        downloadBtn(text, ext: ext, primary: index == 0),
    ];
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
      if (isSkipped(manifest, isAuto: isAuto, skipped: Pref.skippedUpdate)) {
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
        builder: (_) =>
            _UpdateDialog(manifest: manifest, apk: apk, isAuto: isAuto),
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

// 发现新版本：标题、一行灰色的版本信息、能滚动的发版说明、两个次要的小链接；
// 按钮竖排时主按钮（填充）在最上面，「稍后」在最下面
class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.manifest,
    required this.apk,
    required this.isAuto,
  });

  final UpdateManifest manifest;
  // 安卓上匹配设备 ABI 的包；有它才能应用内下载
  final UpdateAsset? apk;
  final bool isAuto;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    Widget downloadBtn(String text, {String? ext, bool primary = false}) =>
        primary
        ? FilledButton(
            onPressed: () => Update.onDownload(manifest, ext: ext),
            child: Text(text),
          )
        // 强调色只给主按钮，次要按钮用正文色
        : TextButton(
            onPressed: () => Update.onDownload(manifest, ext: ext),
            child: Text(text, style: TextStyle(color: colorScheme.onSurface)),
          );
    final apk = this.apk;
    final size =
        apk?.size ??
        (manifest.assets.length == 1 ? manifest.assets.single.size : null);
    final cancel = TextButton(
      onPressed: SmartDialog.dismiss,
      child: Text('取消', style: TextStyle(color: colorScheme.outline)),
    );
    final skip = TextButton(
      onPressed: () {
        SmartDialog.dismiss();
        GStorage.setting.put(SettingBoxKey.skippedUpdate, manifest.versionCode);
      },
      child: Text('跳过此版本', style: TextStyle(color: colorScheme.onSurface)),
    );
    // 从上到下：主按钮、其余下载按钮、跳过此版本、取消
    final topDown = [
      if (apk != null)
        FilledButton(
          onPressed: () => Update._downloadInApp(manifest, apk),
          child: const Text('下载并安装'),
        )
      else
        ...Update.formatButtons(manifest, downloadBtn),
      skip,
      cancel,
    ];
    return AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(
            updateMeta(manifest.tag, size: size, date: manifest.date),
            style: TextStyle(fontSize: 13, color: colorScheme.outline),
          ),
          const SizedBox(height: 14),
          // 说明长时在这块里滚动，按钮和标题不动；提交链接在说明末尾，
          // 看完说明才看得到
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (height * 0.4).clamp(120.0, 320.0),
              ),
              child: FadingScroll(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    ReleaseNoteView(
                      sections: ReleaseNote.parse(manifest.body),
                    ),
                    const SizedBox(height: 8),
                    Transform.translate(
                      offset: const Offset(-4, 0),
                      child: DialogLink(
                        label: '查看这一版的全部提交 ›',
                        onTap: () =>
                            PageUtils.launchURL(Update.commitsUrl(manifest)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // 玻璃的 GlassAlertActions 把 FilledButton 放最上、取消放最下，
      // 其余照给的顺序；Material 的 OverflowBar 一行时主按钮在最右，
      // 竖排时（up）倒过来，主按钮在最上
      actionsOverflowDirection: VerticalDirection.up,
      actions: GlassSurfaces.installed
          ? [cancel, ...topDown.take(topDown.length - 1)]
          : topDown.reversed.toList(),
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
  int _sourceIndex = 0;
  int _received = 0;
  String _message = '';
  File? _file;
  // 签名或版本对不上时再点安装也没用，不给按钮
  bool _canInstall = true;
  // 正在打开安装程序或者等设置页回来，按钮先不能点
  bool _installing = false;
  AppLifecycleListener? _lifecycle;
  // 下载速度：每半秒按这段时间收到的字节算一次
  final _clock = Stopwatch();
  int _speedFrom = 0;
  double? _speed;
  // 装不上时的标题
  String _title = '';

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
        onSource: (_) {
          if (!mounted) return;
          setState(() {
            _sourceIndex++;
            _received = 0;
            _speedFrom = 0;
            _speed = null;
            _clock
              ..reset()
              ..start();
          });
        },
        onProgress: (received, _) {
          if (!mounted) return;
          setState(() {
            _received = received;
            final ms = _clock.elapsedMilliseconds;
            if (ms >= 500) {
              _speed = (received - _speedFrom) * 1000 / ms;
              _speedFrom = received;
              _clock
                ..reset()
                ..start();
            }
          });
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
      _title = '安装新版本';
      _message = '安装包已下载并校验通过，正在打开系统安装程序';
    });
    var res = await AppInstaller.install(file.path);
    if (res == .permission) {
      if (!mounted) return;
      setState(() {
        _title = '需要安装权限';
        _message = '请在设置里允许 PiliPlus 安装应用，返回后会继续安装';
      });
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
      final allowed = await AppInstaller.canInstall();
      // 等的时候对话框可能被关掉了
      if (!mounted) return;
      if (!allowed) {
        setState(() => _message = '没有获得安装应用的权限，无法安装');
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
    _title = switch (res) {
      .started => '安装新版本',
      .signature || .downgrade => '无法覆盖安装',
      .invalid => '安装包已损坏',
      .permission => '需要安装权限',
      .failed => '无法打开安装程序',
    };
    setState(
      () => _message = switch (res) {
        .started => '已打开系统安装程序。如果没有装上，可以点「安装」再试',
        .signature =>
          '安装包的签名和已安装的 PiliPlus 不同（比如现在装的是自己编译的版本），'
              '系统不允许覆盖安装。需要先卸载当前版本再安装；卸载会清除应用数据，'
              '也会删掉这里下好的安装包，卸载后从 GitHub 的 Release 页面下载新版安装',
        .downgrade => '安装包的版本比已安装的低，系统不允许覆盖安装',
        .invalid => '安装包无法解析，已删除，请重新下载',
        .permission => '没有获得安装应用的权限，无法安装',
        .failed => '无法打开系统安装程序，可以点「安装」再试一次',
      },
    );
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final muted = TextStyle(
      fontSize: 13,
      color: colorScheme.outline,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
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
      child: Text('浏览器下载', style: TextStyle(color: colorScheme.onSurface)),
    );
    final failures = _message.split('\n');
    return AlertDialog(
      title: Text(switch (_stage) {
        .downloading => '正在下载',
        .failed => '下载失败',
        .install => _title,
      }),
      // 和「发现新版本」一样宽，换对话框时不跳
      content: SizedBox(
        width: double.maxFinite,
        child: switch (_stage) {
          .downloading => Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              const SizedBox(height: 4),
              // 还在连下载源时没有进度，给不定进度条
              LinearProgressIndicator(
                value: _received > 0 && total > 0 ? _received / total : null,
                minHeight: 6,
                borderRadius: const .all(.circular(3)),
              ),
              const SizedBox(height: 4),
              // 定高，换下载源的链接没了也不跳
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    // 窄屏、大字号时这段让位给右边的链接
                    Expanded(
                      child: Text(
                        _speed == null
                            ? '${_mb(_received)} / ${_mb(total)} MB'
                            : '${_mb(_received)} / ${_mb(total)} MB · '
                                  '${_mb(_speed!.round())} MB/s',
                        style: muted,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                    // 卡住时换一个下载源；已经是最后一个就不给
                    if (_sourceIndex < updateMirrors.length - 1)
                      Transform.translate(
                        offset: const Offset(4, 0),
                        child: DialogLink(
                          label: '换下载源',
                          onTap: () => _downloader?.skip(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 长的提示在横屏或大字号下也要看得全
          .failed => SingleChildScrollView(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                const Text('没能下载安装包，可以重试，或者用浏览器下载。'),
                const SizedBox(height: 10),
                for (final line in failures) Text(line, style: muted),
              ],
            ),
          ),
          .install => SingleChildScrollView(child: Text(_message)),
        },
      ),
      // 一行放得下时主按钮在最右，竖排时在最上
      actionsOverflowDirection: VerticalDirection.up,
      actions: switch (_stage) {
        .downloading => [cancel],
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
