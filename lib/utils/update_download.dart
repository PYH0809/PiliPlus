import 'dart:io';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/update.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts/account_manager/account_mgr.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

// 安装包的下载源，按顺序试，前一个超时、出错或校验不过就换下一个。
// 前缀接在 GitHub 地址前面，空串是 GitHub 直连。
// 2026-11 从国内测的 4 MB：gh-proxy.com 2.8 MB/s，ghfast.top 1.5 MB/s，
// GitHub 2.4 MB/s；ghproxy.net 太慢，gh.llkk.cc 挂了，没放进来
const updateMirrors = ['https://gh-proxy.com/', 'https://ghfast.top/', ''];

typedef UpdateFetch = Future<void> Function(
  String url,
  String savePath, {
  required CancelToken cancelToken,
  required void Function(int received) onProgress,
});

class UpdateDownloadException implements Exception {
  // 每个下载源失败的原因
  final List<String> failures;
  const UpdateDownloadException(this.failures);

  @override
  String toString() => failures.join('\n');
}

class UpdateDownloader {
  final UpdateManifest manifest;
  final UpdateAsset asset;
  final String dir;
  final List<String> mirrors;
  final UpdateFetch fetch;

  UpdateDownloader({
    required this.manifest,
    required this.asset,
    required this.dir,
    this.mirrors = updateMirrors,
    this.fetch = _dioFetch,
  });

  CancelToken? _token;
  bool _cancelled = false;
  bool _skipping = false;

  static List<String> sources(
    String url, [
    List<String> mirrors = updateMirrors,
  ]) => [for (final prefix in mirrors) '$prefix$url'];

  // 给用户看的下载源名字
  static String sourceName(String url) {
    final host = Uri.parse(url).host;
    return host == 'github.com' ? 'GitHub' : host;
  }

  static Future<String> sha256OfFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<bool> verify(File file, UpdateAsset asset) async =>
      await file.length() == asset.size &&
      await sha256OfFile(file) == asset.sha256;

  File get file => File('$dir/${asset.name}');

  // 停下整个下载；run 返回 null
  void cancel() {
    _cancelled = true;
    _token?.cancel();
  }

  // 放弃当前下载源，换下一个
  void skip() {
    _skipping = true;
    _token?.cancel();
  }

  // 下好并校验过的安装包；取消时返回 null，所有下载源都失败或者缓存目录
  // 读写出错时抛 UpdateDownloadException。onSource 在换到一个下载源时调用
  Future<File?> run({
    void Function(String source)? onSource,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      return await _run(onSource, onProgress);
    } on FileSystemException catch (e) {
      // 比如下载时缓存被清掉了
      throw UpdateDownloadException(['缓存目录读写出错：${e.message} ${e.path ?? ''}']);
    }
  }

  Future<File?> _run(
    void Function(String source)? onSource,
    void Function(int received, int total)? onProgress,
  ) async {
    final target = file;
    if (target.existsSync() && await verify(target, asset)) return target;

    final folder = Directory(dir);
    await folder.create(recursive: true);
    final part = File('${target.path}.part');
    // 以前版本的安装包
    for (final i in folder.listSync()) {
      if (i.path != target.path && i.path != part.path) _delete(File(i.path));
    }
    final failures = <String>[];
    for (final url in sources(UpdateHttp.assetUrl(manifest, asset), mirrors)) {
      if (_cancelled) break;
      final name = sourceName(url);
      onSource?.call(name);
      _skipping = false;
      final token = _token = CancelToken();
      try {
        await fetch(
          url,
          part.path,
          cancelToken: token,
          onProgress: (received) => onProgress?.call(received, asset.size),
        );
      } on FileSystemException {
        rethrow;
      } catch (e) {
        _delete(part);
        if (_cancelled) break;
        failures.add('$name：${_skipping ? '已跳过' : _describe(e)}');
        continue;
      }
      if (_cancelled) {
        _delete(part);
        break;
      }
      if (!await verify(part, asset)) {
        _delete(part);
        failures.add('$name：文件校验不通过');
        continue;
      }
      _delete(target);
      return part.renameSync(target.path);
    }
    if (_cancelled) return null;
    throw UpdateDownloadException(failures);
  }

  static void _delete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static String _describe(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode case final code?) return 'HTTP $code';
      return switch (e.type) {
        .connectionTimeout => '连接超时',
        .receiveTimeout => '下载超时',
        .connectionError => '连接失败',
        _ => '${e.error ?? e.message ?? e.type}',
      };
    }
    return '$e';
  }

  // 镜像和 GitHub 都会跳转，HTTP/1.1 的 dio 由 HttpClient 自己跟
  static Future<void> _dioFetch(
    String url,
    String savePath, {
    required CancelToken cancelToken,
    required void Function(int received) onProgress,
  }) => Request.http11Dio.download(
    url,
    savePath,
    cancelToken: cancelToken,
    onReceiveProgress: (received, _) => onProgress(received),
    options: Options(
      // 安装包要原样的字节，压缩过的哈希对不上
      headers: {'user-agent': BrowserUa.mob, 'accept-encoding': 'identity'},
      receiveTimeout: const Duration(seconds: 15),
      // 一个下载源失败就换下一个，不要拦截器每次都弹「服务器异常」
      extra: {'account': const NoAccount(), AccountManager.silent: true},
    ),
  );
}
