import 'dart:convert';
import 'dart:io' show Platform;

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts/account_manager/account_mgr.dart';
import 'package:dio/dio.dart';

abstract final class UpdateHttp {
  // 测试用：--dart-define=pili.updateRelease=<地址> 把清单和安装包都换成
  // <地址>/<os>.json 和 <地址>/<tag>/<文件名>
  static const _releaseOverride = String.fromEnvironment('pili.updateRelease');

  static String get manifestUrl =>
      '${_releaseOverride.isNotEmpty ? _releaseOverride : Api.latestRelease}'
      '/${Platform.operatingSystem}.json';

  static String get downloadBase =>
      _releaseOverride.isNotEmpty ? _releaseOverride : Api.releaseDownload;

  static String assetUrl(UpdateManifest manifest, UpdateAsset asset) =>
      '$downloadBase/${Uri.encodeComponent(manifest.tag)}/'
      '${Uri.encodeComponent(asset.name)}';

  // 清单从 GitHub 直接读，不走镜像：安装包靠它里面的 SHA-256 校验。
  // 404 是这个平台的包还没传完（或者还没有 Release），code 留着给调用方区分。
  // 这个地址要经过两次 302，用 HTTP/1.1 的 dio：它的跳转由 HttpClient 自己跟，
  // 不靠只在重试次数非 0 时才装上的 RetryInterceptor
  static Future<LoadingState<UpdateManifest>> manifest() async {
    try {
      final res = await Request.http11Dio.get<String>(
        manifestUrl,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          responseType: ResponseType.plain,
          extra: {'account': const NoAccount()},
        ),
      );
      return parseResponse(res.statusCode, res.data);
    } on DioException catch (e) {
      return parseResponse(e.response?.statusCode ?? -1, {
        'message': await AccountManager.dioError(e),
      });
    }
  }

  static LoadingState<UpdateManifest> parseResponse(int? code, Object? data) {
    switch (code) {
      case 200:
        try {
          return Success(UpdateManifest.fromJson(jsonDecode(data as String)));
        } catch (e) {
          return Error('检查更新失败，更新信息格式有误：$e', code: code);
        }
      case 404:
        return const Error('新版本的安装包还在上传，请稍后再试', code: 404);
      case 403 || 429:
        return Error('检查更新失败，GitHub 限制了访问频率（HTTP $code），请稍后再试', code: code);
      case -1 || null:
        final msg = data is Map ? data['message'] : null;
        return Error('检查更新失败，无法连接 GitHub：${msg ?? '网络异常'}', code: code);
      default:
        return Error('检查更新失败，GitHub 返回了 HTTP $code', code: code);
    }
  }
}
